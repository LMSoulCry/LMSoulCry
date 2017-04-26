program LMSoulCry;

uses
  Vcl.Forms,
  MainForm in 'MainForm.pas' {AppForm},
  Wcrypt2 in 'Wcrypt2.pas',
  Vcl.Themes,
  Vcl.Styles;

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  TStyleManager.TrySetStyle('Tablet Light');
  Application.CreateForm(TAppForm, AppForm);
  Application.Run;
end.
