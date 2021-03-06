unit uOSCReader;

interface

uses Windows, Classes,SysUtils, Forms, MMSystem;

type  TDwordArray   = array [0..0] of DWORD;
type  TDoubleArray  = array [0..0] of Double;
type  PDwordArray    = ^TDwordArray;
type  PDoubleArray   = ^TDoubleArray;

type TOSCHeader = record
  sLogo1      : array[0..5] of Char;   //OSC
  iVersion    : Word;
  iSampleRate : DWORD;
  sUnkn1      : array[0..11] of Char;
  sLogo2      : array[0..7] of Char;  // ZOOMBIAS
  sUnkn2      : array[0..18] of Char;
  sADATA      : array[0..4] of Char;
  iDataSize   : DWORD;
end;

type  fNoticeCallBack  = procedure (aData : Pointer); stdcall;
type  PNoticeCallBack = ^fNoticeCallBack;
type  TReadData = procedure (aData : PDoubleArray; aSize : DWORD) of object;

type TOSCReader = class
  private
    FOnReadData : TReadData;
    fSampleRate : dword;
    fDataArray  : array of Double;
    fCaptureIsReady  : Boolean;
    IsStopped : Boolean;

    procedure SetOnReadData( Value: TReadData);
    procedure SetSampleRate( Value: Dword);
  protected

  public
    procedure StartCapture; virtual;
    procedure StopCapture;  virtual;
    property  SampleRate : dword read fSampleRate write SetSampleRate;
    property  OnReadData : TReadData read FOnReadData write SetOnReadData;
    constructor Create;// (aSampleRate : DWORD);
    destructor Destroy;
end;

type TOSCReaderDevice = class(TOSCReader)
      private
        fChannelNum : Integer;
        
      protected

      public
        SampleAvaibleList : TStringList;
        procedure StartCapture; override;
        procedure StopCapture;  override;
        constructor Create(aChannelNum : Integer);
        destructor Destroy;
end;

type TOSCReaderFile = class(TOSCReader)
      private
        fName : string;
        fHandle : Integer;
        fOSC_OSCHeader : TOSCHeader;
        fDataSize : Integer;
        fDataArray : PByteArray;
        FILE_CACHE_SIZE : DWORD;
      protected

      public
        procedure StartCapture; override;
        procedure StopCapture;  override;
        constructor Create (FileName : string);
        destructor Destroy;
end;

implementation
    var
    fRealLength, fCaptureLength : DWORD;
    aSampleAvaibleList : TStringList;
    DataIsReady      : Boolean;
    DeviceIsReady    : Boolean;
    OSCDoubleBuff    : PDoubleArray;
    ReadBytesFromOSC : DWORD;
    ChannelNum : Integer;

function InitDll : integer;                   stdcall; external 'VDSO.dll' name '_InitDll@0';
function FinishDll : integer;                 stdcall; external 'VDSO.dll' name '_FinishDll@0';
function GetOscSupportSampleNum : integer;    stdcall; external 'VDSO.dll' name '_GetOscSupportSampleNum@0';
function IsDevAvailable         : integer;    stdcall; external 'VDSO.dll' name '_IsDevAvailable@0';
procedure SetDevNoticeCallBack (aData : Pointer; AddCallBack :PNoticeCallBack; RemoveCallBack :PNoticeCallBack); stdcall; external 'VDSO.dll' name '_SetDevNoticeCallBack@12';
procedure SetDataReadyCallBack (aData : Pointer; DataReadyCallBack : PNoticeCallBack); stdcall; external 'VDSO.dll' name '_SetDataReadyCallBack@8';
function Capture(Capture_length : integer): integer;    stdcall; external 'VDSO.dll' name '_Capture@4';
function SetOscSample(Sample : Dword) : integer;    stdcall; external 'VDSO.dll' name '_SetOscSample@4';
function IsDataReady: integer;    stdcall; external 'VDSO.dll' name '_IsDataReady@0';
function GetOscSupportSamples (Samples : Pointer; NumSamples : Integer) : integer;      stdcall; external 'VDSO.dll' name '_GetOscSupportSamples@8';
function ReadVoltageDatas  (Channel : Integer; DoubleArray : Pointer; DataLen : DWORD) : Dword;      stdcall; external 'VDSO.dll' name '_ReadVoltageDatas@12';
function SetOscChannelRange(Channel,  Minmv, Maxmv: Integer) : integer;      stdcall; external 'VDSO.dll' name '_SetOscChannelRange@12';
function GetMemoryLength :dword;  stdcall; external 'VDSO.dll' name '_GetMemoryLength@0';


{ TOSC }



constructor TOSCReader.Create;//(aSampleRate : DWORD);
begin
   // SampleRate:=aSampleRate;
    aSampleAvaibleList:=TStringList.Create;
    DataIsReady   := False;
    DeviceIsReady := False;
    IsStopped     := False;
end;

destructor TOSCReader.Destroy;
begin
 aSampleAvaibleList.Free;
end;

procedure TOSCReader.SetOnReadData( Value: TReadData);
begin
  FOnReadData := Value;
end;

procedure TOSCReader.SetSampleRate( Value: Dword);
begin
   fSampleRate := Value;
end;

procedure TOSCReader.StartCapture;
begin
 IsStopped:=False;
end;

procedure TOSCReader.StopCapture;
begin
  IsStopped := True;
end;

{ TOSCReaderDevice }

procedure DevRemoveCallBack (aData : Pointer);stdcall;
begin
  //ShowMessage('RemoveCallBack');
end;

procedure DevNoticeCallBack (aData : Pointer); stdcall;
var
sample_num,i : Integer;
smpArr       : PDwordArray;
begin
  sample_num:=GetOscSupportSampleNum();
  SetOscChannelRange(0,-6000,6000);
  fCaptureLength:=GetMemoryLength();

  GetMem(smpArr, sample_num * SizeOf(DWORD));
  GetOscSupportSamples(smpArr,sample_num);

  for i:=0 to sample_num-1 do
  begin
     aSampleAvaibleList.Add(Format('%d',[smpArr[i]]));
  end;

  SetOscSample(smpArr[i-1] div 2);
  //SetOscSample(12000000);
  DeviceIsReady:=True;

end;

procedure DataReadyCallBack (aData : Pointer);stdcall;
begin
  ReadBytesFromOSC := ReadVoltageDatas(ChannelNum,  OSCDoubleBuff, fRealLength);
  DataIsReady:=true;
end;

constructor TOSCReaderDevice.Create(aChannelNum : Integer);
var
  stTime : DWORD;
begin
  inherited Create();

  if InitDll() <> 1 then
     Raise Exception.CreateFmt('Unable init : ''%s''', ['VDSO.dll']);

     stTime:=timeGetTime;

     aSampleAvaibleList := TStringList.Create;
     SampleAvaibleList := TStringList.Create;
     ChannelNum:=aChannelNum;
     fChannelNum:=aChannelNum;


     SetDevNoticeCallBack (nil,@DevNoticeCallBack, @DevRemoveCallBack);
     SetDataReadyCallBack (nil, @DataReadyCallBack );

     DeviceIsReady:=false;

   while not DeviceIsReady do
   begin
     Application.ProcessMessages;
     if timeGetTime > stTime + 5000 then
      Raise Exception.CreateFmt('Capture standby has failed %d. Device is connected?', [5000]);
   end;

   SampleAvaibleList := aSampleAvaibleList;
   if  SampleAvaibleList.Count <= 0  then
      Raise Exception.CreateFmt('Failed to set samplerate %d. Device is connected?', [SampleAvaibleList.Count]);
   try
    SampleRate := StrToInt(SampleAvaibleList[SampleAvaibleList.Count-1]) div 2;
    except
      Raise Exception.CreateFmt('Failed to set samplerate %d. Device is connected?', [SampleAvaibleList.Count]);
      end;
end;

destructor TOSCReaderDevice.Destroy;
begin

 FinishDll();
 SampleAvaibleList.Free;
  inherited;
end;

procedure TOSCReaderDevice.StopCapture;
begin
  inherited;
end;

procedure TOSCReaderDevice.StartCapture;
var
  stTime : DWORD;
begin
  inherited;
  stTime:=timeGetTime;
  GetMem(OSCDoubleBuff, fCaptureLength*1024*sizeof(double));

   while not IsStopped do
   begin
     stTime:=timeGetTime;
     DataIsReady:=false;

    fRealLength:=Capture(fCaptureLength);
    fRealLength:=fRealLength * 1024;

     while not DataIsReady  do
     begin
     Application.ProcessMessages;
          if timeGetTime > stTime + 5000 then
          Raise Exception.CreateFmt('Waiting for data resulted in an error : %d', [5000]);
     end;

     if Assigned (OnReadData) then
     OnReadData(OSCDoubleBuff  , ReadBytesFromOSC);

    // FreeMem(OSCDoubleBuff);
   end;
  FreeMem(OSCDoubleBuff);
end;



{ TOSCReaderFile }

constructor TOSCReaderFile.Create(FileName: string);
    var
    sr : TSearchRec;
begin
  FindFirst(FileName, faAnyFile, sr);

  fHandle :=FileOpen(FileName,fmOpenRead or fmShareDenyNone);

  if (FileRead (fHandle,fOSC_OSCHeader,SizeOf(fOSC_OSCHeader))<=0)  then
   Raise Exception.CreateFmt('Unable FileRead! : ''%s''', [FileName]);

   SampleRate:=fOSC_OSCHeader.iSampleRate;
   fDataSize :=fOSC_OSCHeader.iDataSize;

   FILE_CACHE_SIZE := 1024000;
   GetMem(OSCDoubleBuff, (FILE_CACHE_SIZE+1)*sizeof(double));
   GetMem(fDataArray, FILE_CACHE_SIZE+1);
end;

destructor TOSCReaderFile.Destroy;
begin
   FreeMem(OSCDoubleBuff);
   FreeMem(fDataArray);
end;

procedure TOSCReaderFile.StartCapture;
var
  rCount,i : DWORD;
begin
  inherited;
  rCount := 1;
  while  (rCount > 0) and (IsStopped = False) do
  begin
    Application.ProcessMessages;
     rCount := FileRead (fHandle,fDataArray^, FILE_CACHE_SIZE);
     if rCount <= 0 then Break;
     
     if Assigned(OnReadData) then
     begin
       for i:=0 to rCount-1 do
       begin
         OSCDoubleBuff[i]:=fDataArray[i];
         OSCDoubleBuff[i]:=(12/2-(12*OSCDoubleBuff[i]/255))*-1;
       end;
       OnReadData(OSCDoubleBuff , rCount-1);
     end;
  end;

end;



procedure TOSCReaderFile.StopCapture;
begin
  inherited;
//
end;

end.
