(*
  �������� ������� ��� LMNoIpServer.exe
  ������������ ������ � ������������� �����
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

    // ����������� �������� �������� ���� �� Server
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

    // ���������� AES ����
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

    // ��������� AES, ���������� ������
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

    // ������ AES �����
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
  ���� ����� ���������� � ��������� �������, ��� ������ ���������� � ������
  ������������. � ��� � ������������ ������ �� ���������� � ��������� ������� LM,
  ������������� ��� � LMNoIpServer.exe
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
      // ������� ������
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      if Val32 <> 1 then
        Exit;

      // ������ ����� ��� ����������
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));

      // ��� ���������� ��� ���������� == 3, ��� ����� Server <> NOIP
      if Val32 <> 3 then
        Exit;

      // ������ �� ������� Viewer, ��������, 00 00 12 d4, �� ���� 4820
      Val32 := Client.IOHandler.ReadInt32();
      //OutputDebug('Version: ' + Val32.ToString);
      AContext.Connection.IOHandler.Write(Int32(Val32));

      // ������ �� ������� Server
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      //OutputDebug('Version Server: ' + Val32.ToString);

      // 00 00 00 02
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      //OutputDebug('00 00 00 02: ' + Val32.ToString);
      if Val32 <> 2 then
        Exit;

      // �����-�� ������, ������ "--"
      S := AContext.Connection.IOHandler.ReadLn();
      Client.IOHandler.WriteLn(S);
      //OutputDebug('Some string: ' + S);

      // ID �������� �� �������!
      Id := AContext.Connection.IOHandler.ReadLn();
      Client.IOHandler.WriteLn(Id);
      //OutputDebug('ID: ' + Id);

      // ��������, ���� �� ID � ������ �������������
      FIgnoreListCS.Enter;
      try
        if FIgnoreList.IndexOf(Id) >= 0 then
          Exit;
      finally
        FIgnoreListCS.Leave;
      end;

      // ID � ������� UTF-16 �����-��
      S := AContext.Connection.IOHandler.ReadLn(IndyTextEncoding_UTF16LE);
      Client.IOHandler.WriteLn(S, IndyTextEncoding_UTF16LE);
      //OutputDebug('ID UTF-16: ' + S);

      // ����� ������ ������� �� � NOIP, � � Server
      // ������ ����� ��� ����������, ��� ����������� ��� ������ 3
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));

      // ���� �� 3, �� ��� �� ���������
      if Val32 <> 3 then
        Exit;

      // �����-�� ���������� GUID
      S := Client.IOHandler.ReadLn();
      AContext.Connection.IOHandler.WriteLn();
      //OutputDebug('GUID: ' + S);

      // ���� �� �����, ������� �����������, ������ == 0 � ������������ ��� ��������
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      if Val32 <> 0 then
        Exit;

      // ���������� ����� 00 00 03 09 (777) �� ������� Viewer
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));
      //OutputDebug('777 - 1: ' + Val32.ToString);
      if Val32 <> 777 then
        Exit;

      // ���������� ����� 00 00 03 09 (777) �� ������� Server
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      //OutputDebug('777 - 2: ' + Val32.ToString);
      if Val32 <> 777 then
        Exit;

      // ����� ������, ��������, 00 00 12 d4 (4820)
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));

      // �����-�� �����, ������ 00 00 00 01
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));

      // �����-�� �����, ������ 00 00 00 00
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));

      // �����-�� ������ ������ ������, ���� �� �������� ��������� 0d 0a
      S := AContext.Connection.IOHandler.ReadLn();
      Client.IOHandler.WriteLn(S);

      // ������ ����� �����-�� ��������� �����������,
      // ������ ���� == 3 �� ������ ��������
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      Client.IOHandler.Write(Int32(Val32));
      if Val32 <> 3 then
        Exit;

      // ����� ������ �� ������� Viewer
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));

      // 4 ����� �����
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));
      // ��� 4 ����� �����
      Val32 := Client.IOHandler.ReadInt32();
      AContext.Connection.IOHandler.Write(Int32(Val32));

      // ���������� ������ � RSA, ����� ������������� � ��������� �����

      // ������ ������ RSA ������, �� ���� �� �������� ���!
      Val32 := AContext.Connection.IOHandler.ReadInt32;
      //OutputDebug('RSA open key size: ' + Val32.ToString);

      // ��������� ������ RSA �����, �� �� �������� ��!
      Data := TMemoryStream.Create;
      try
        AContext.Connection.IOHandler.ReadStream(Data, Val32);
        Data.Position := 0;
        SetLength(RealPublicKeyData, Data.Size);
        Data.Read(RealPublicKeyData, Data.Size);
      finally
        FreeAndNil(Data);
      end;

      // ����������� �������� RSA ���� � ����������� AES (������ ������ ������ ��������� Viewer)
      if not GenerateRealSessionKey(RealPublicKeyData, RealSessionKeyData) then
      begin
        OutputDebug('GenerateRealSessionKey error');
        Exit;
      end;

      // ���������� ����� (fake) RSA ���� � �������� ��� ������ �������
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

        // ������� ����� �������� � �������� �����
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

        // ��������� �������� ����, ���������� ������
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

        // ������ ��������� �����
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

      // �������� �� Viewer ����� RSA ����
      Data := TMemoryStream.Create;
      try
        Data.Write(PublicKeyData[0], Length(PublicKeyData));
        Data.Position := 0;

         // ������ ������ ����� RSA
        Val32 := Data.Size;
        //OutputDebug('RSA open key NEW size: ' + Val32.ToString);
        Client.IOHandler.Write(Int32(Val32));
        // ������
        Client.IOHandler.Write(Data, Data.Size);
      finally
        FreeAndNil(Data);
      end;

      // ��������� ������ AES �����
      Size := Client.IOHandler.ReadInt32();

      // �������� ������ ��������� AES ����� �� Server
      Val32 := Length(RealSessionKeyData);
      AContext.Connection.IOHandler.Write(Int32(Val32));

      Data := TMemoryStream.Create;
      PasswordData := TMemoryStream.Create;
      try
        // ��������� AES ����
        Client.IOHandler.ReadStream(Data, Size);
        //OutputDebug('AES key from Viewer: ' + Val32.ToString);

        // �������� ������ AES �����
        SetLength(SessionKeyData, Data.Size);
        Data.Position := 0;
        Data.Read(SessionKeyData, Data.Size);

        // �������� �������� AES ���� �� Server
        Data.Clear;
        Data.Write(RealSessionKeyData, Length(RealSessionKeyData));
        Data.Position := 0;
        AContext.Connection.IOHandler.Write(Data, Data.Size);

        // � ��� ���������� ������ �������� ������������ �� ������
        // � LM ���� � ������ ���� ������������, ��� ���������� == 1
        Val32 := AContext.Connection.IOHandler.ReadInt32;
        if Val32 <> 1 then
        begin
          // ��������� ���� ���� ID �� �������������
          IgnoreId(Id);
          Exit;
        end;

        // � Server ������ �� ��������, ���, ��� ���������� ��� ��������

        // �������� ������
        Client.IOHandler.Write(Int32(1));

        // ��������� ������ ������ � ������������� �������
        Val32 := Client.IOHandler.ReadInt32();
        // ��������� ������������� ������
        Client.IOHandler.ReadStream(PasswordData, Val32);

        // ����� � ����� ������ �� �������� � ���� ������ � ���������� � ������� ���� ID
        IgnoreId(Id);

        // ����������� ������ AES �����
        Data.Clear;
        Data.Write(SessionKeyData, Length(SessionKeyData));
        Data.Position := 0;

        FCryptoAPICS.Enter;
        try
          // ������ AES �����
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

          // ������� ������������ ������ AES ������
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
      // ������������� �������, ��� ��������� � �������, � LMNoIpServer.exe
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

  // ������ ����
  SendMessage(Output.Handle, EM_LINESCROLL, 0, Output.Lines.Count);
end;

end.
