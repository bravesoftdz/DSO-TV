program oscst;

uses
  Forms,
  main in 'main.pas' {Form1},
  uOSCReader in '..\uOSCReader.pas',
  uOSCTV in '..\uOSCTV.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
