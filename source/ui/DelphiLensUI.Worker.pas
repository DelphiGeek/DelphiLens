unit DelphiLensUI.Worker;

interface

//TODO: Catch exceptions in worker and report them back

uses
  OtlSync, OtlComm, OtlTaskControl,
  DelphiLens.Intf,
  DelphiLensUI.UIXStorage,
  DelphiLensUI.UIXEngine.Intf;

type
  TDLUIProjectConfig = record
    PlatformName      : string;
    ConditionalDefines: string;
    SearchPath        : string;
    constructor Create(const APlatform, AConditionalDefines, ASearchPath: string);
  end; { TDLUIProjectConfig }

  TDLUINavigationInfo = record
  private
    FileNameStr: string;
  public
    FileName  : PChar;
    Line      : integer;
    Column    : integer;
    constructor Create(const location: TDLUIXLocation);
  end; { TDLUINavigationInfo }
  PDLUINavigationInfo = ^TDLUINavigationInfo;

  TDelphiLensUIProject = class
  strict private
    FCurrentRescanID: integer;
    FCurrentResultID: integer;
    FNavigationInfo : TDLUINavigationInfo;
    FProjectName    : string;
    FScanLock       : IOmniCriticalSection;
    FScanResult     : IDLScanResult;
    FUIXStorage     : IDLUIXStorage;
    FWorker         : IOmniTaskControl;
  protected
    procedure ScanComplete(const result: IDLScanResult; scanID: integer);
  public
    constructor Create(const projectName: string);
    destructor  Destroy; override;
    procedure Activate(monitorNum: integer; const fileName: string;
      line, column: integer; const tabNames: string; var navigate: boolean);
    procedure FileModified(const fileName: string);
    function  GetNavigationInfo: PDLUINavigationInfo; inline;
    procedure ProjectModified;
    procedure Rescan;
    procedure SetConfig(const config: TDLUIProjectConfig);
  end; { TDelphiLensUIProject }

var
  GLogHook: procedure (projectID: integer; const msg: PChar); stdcall; //TDLLogger;

implementation

uses
  System.UITypes,
  System.SysUtils,
  Vcl.Forms,
  Spring,
  DSiWin32,
  OtlCommon,
  DelphiLens,
  DelphiLensUI.Main, DelphiLensUI.WorkerContext;

const
  MSG_RESCAN = 1;

type
  TDelphiLensUIWorker = class(TOmniWorker)
  strict private const
    CTimerRescan         = 1;
    CTimerRescanDelay_ms = 3000;
  var
    FDelphiLens: IDelphiLens;
    FOwner     : TDelphiLensUIProject;
    FScanLock  : IOmniCriticalSection;
    FScanID    : TOmniAlignedInt32;
  strict protected
    procedure ReportException(const funcName: string; E: Exception);
    procedure ScheduleRescan;
  protected
    function  Initialize: boolean; override;
  public
    procedure Open(const projectName: TOmniValue);
    procedure Close;
    procedure ProjectModified;
    procedure FileModified(const fileModified: TOmniValue);
    procedure Rescan(var msg: TOmniMessage); message MSG_RESCAN;
    procedure SetConfig(const configInfo: TOmniValue);
    procedure TimerRescan;
  end; { TDelphiLensUIWorker }

{ TDLUIProjectConfig }

constructor TDLUIProjectConfig.Create(const APlatform, AConditionalDefines,
  ASearchPath: string);
begin
  PlatformName := APlatform;
  ConditionalDefines := AConditionalDefines;
  SearchPath := ASearchPath;
end; { TDLUIProjectConfig.Create }

{ TDelphiLensUIProject }

constructor TDelphiLensUIProject.Create(const projectName: string);
begin
  inherited Create;
  FProjectName := projectName;
  FScanLock := CreateOmniCriticalSection;
  FWorker := CreateTask(TDelphiLensUIWorker.Create(), 'DelphiLens engine for ' + projectName)
               .SetParameter('owner', Self)
               .SetParameter('lock', FScanLock)
               .Unobserved
               .Run;
  FWorker.Invoke(@TDelphiLensUIWorker.Open, projectName);
  FUIXStorage := CreateUIXStorage;
end; { TDelphiLensUIProject.Create }

destructor TDelphiLensUIProject.Destroy;
begin
  if assigned(FWorker) then
    FWorker.Invoke(@TDelphiLensUIWorker.Close);
  FWorker.Terminate;
  FWorker := nil;
  inherited;
end; { TDelphiLensUIProject.Destroy }

procedure TDelphiLensUIProject.Activate(monitorNum: integer; const fileName: string;
  line, column: integer; const tabNames: string; var navigate: boolean);
var
  context  : IDLUIWorkerContext;
  oldCursor: TCursor;
  unitName : string;
begin
  unitName := ExtractFileName(fileName);
  if DSiFileExtensionIs(unitName, ['.pas', '.dpr', '.dpk']) then
    unitName := ChangeFileExt(unitName, '');

  oldCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;

  repeat
    FScanLock.Acquire;
    try
      Application.ProcessMessages;
      //TODO: Show nicer "Please wait" window with TActivityIndicator
      Screen.Cursor := oldCursor;

      if not assigned(FScanResult) then
        //TODO: Report error
  //      Console.Writeln('Activate: Project = nil')
  //      break; //repeat
      else if FCurrentResultID >= FCurrentRescanID then begin // may run ahead because of the timer
        context := CreateWorkerContext(FUIXStorage, FProjectName, FScanResult,
          TDLUIXLocation.Create(fileName, unitName, line, column),
          tabNames.Split([#13]), monitorNum);
        DLUIShowUI(context);
        break; //repeat
      end
      else
    finally
      FScanLock.Release;
    end;
  until false;

  navigate := assigned(context) and context.Target.HasValue;
  if navigate then
    FNavigationInfo := TDLUINavigationInfo.Create(context.Target);
end; { TDelphiLensUIProject.Activate }

procedure TDelphiLensUIProject.FileModified(const fileName: string);
begin
  FWorker.Invoke(@TDelphiLensUIWorker.FileModified, fileName);
end; { TDelphiLensUIProject.FileModified }

function TDelphiLensUIProject.GetNavigationInfo: PDLUINavigationInfo;
begin
  Result := @FNavigationInfo;
end; { TDelphiLensUIProject.GetNavigationInfo }

procedure TDelphiLensUIProject.ProjectModified;
begin
  FWorker.Invoke(@TDelphiLensUIWorker.ProjectModified);
end; { TDelphiLensUIProject.ProjectModified }

procedure TDelphiLensUIProject.Rescan;
var
  waiter: IOmniWaitableValue;
begin
  waiter := CreateWaitableValue;
  FWorker.Comm.Send(MSG_RESCAN, waiter);
  waiter.WaitFor; //TODO: Add timeout, report error
  FCurrentRescanID := waiter.Value;
end; { TDelphiLensUIProject.Rescan }

procedure TDelphiLensUIProject.ScanComplete(const result: IDLScanResult; scanID: integer);
begin
  FScanResult := result;
  FCurrentResultID := scanID;
end; { TDelphiLensUIProject.ScanComplete }

procedure TDelphiLensUIProject.SetConfig(const config: TDLUIProjectConfig);
begin
  FWorker.Invoke(@TDelphiLensUIWorker.SetConfig, TOmniValue.FromRecord<TDLUIProjectConfig>(config))
end; { TDelphiLensUIProject.SetConfig }

{ TDelphiLensUIWorker }

procedure TDelphiLensUIWorker.Close;
begin
  try
    FDelphiLens := nil;
  except
    on E:Exception do
      ReportException('Close', E);
  end;
end; { TDelphiLensUIWorker.Close }

procedure TDelphiLensUIWorker.FileModified(const fileModified: TOmniValue);
begin
  try
    ScheduleRescan;
  except
    on E:Exception do
      ReportException('FileModified', E);
  end;
end; { TDelphiLensUIWorker.FileModified }

function TDelphiLensUIWorker.Initialize: boolean;
begin
  Result := inherited Initialize;
  if Result then begin
    FOwner := Task.Param['owner'];
    FScanLock := Task.Param['lock'].AsInterface as IOmniCriticalSection;
    FScanID.Value := 0;
  end;
end; { TDelphiLensUIWorker.Initialize }

procedure TDelphiLensUIWorker.Open(const projectName: TOmniValue);
begin
  try
    FDelphiLens := CreateDelphiLens(projectName);
  except
    on E:Exception do
      ReportException('Open', E);
  end;
end; { TDelphiLensUIWorker.Open }

procedure TDelphiLensUIWorker.ProjectModified;
begin
  try
    ScheduleRescan;
  except
    on E:Exception do
      ReportException('ProjectModified', E);
  end;
end; { TDelphiLensUIWorker.ProjectModified }

procedure TDelphiLensUIWorker.ReportException(const funcName: string;
  E: Exception);
begin
  //TODO: Temporary solution
//  Console.Writeln(['Worker exception in ', funcName, ' ', E.ClassName, ': ', E.Message]);
end; { TDelphiLensUIWorker.ReportException }

procedure TDelphiLensUIWorker.Rescan(var msg: TOmniMessage);
var
  scanResult: IDLScanResult;
begin
  try
    FScanID.Increment;
    if not msg.MsgData.IsEmpty then
      (msg.MsgData.AsInterface as IOmniWaitableValue).Signal(FScanID.Value);
    if not assigned(FDelphiLens) then
      Exit;

    Task.ClearTimer(CTimerRescan);

    FScanLock.Acquire;
    try
      scanResult := FDelphiLens.Rescan;
    finally FScanLock.Release; end;

    Task.Invoke(
      procedure
      begin
        FOwner.ScanComplete(scanResult, FScanID.Value);
      end);
  except
    on E:Exception do
      ReportException('Rescan', E);
  end;
end; { TDelphiLensUIWorker.Rescan }

procedure TDelphiLensUIWorker.ScheduleRescan;
begin
  try
    if assigned(FDelphiLens) then
      Task.SetTimer(CTimerRescan, CTimerRescanDelay_ms, @TDelphiLensUIWorker.TimerRescan);
  except
    on E:Exception do
      ReportException('ScheduleRescan', E);
  end;
end; { TDelphiLensUIWorker.ScheduleRescan }

procedure TDelphiLensUIWorker.SetConfig(const configInfo: TOmniValue);
var
  config: TDLUIProjectConfig;
begin
  try
    if assigned(FDelphiLens) then begin
      config := configInfo.ToRecord<TDLUIProjectConfig>;
      { TODO : Implement: SetProjectConfig }
  //    FDelphiLens.Platform := config.PlatformName;
      FDelphiLens.ConditionalDefines := config.ConditionalDefines;
      FDelphiLens.SearchPath := config.SearchPath;
    end;
  except
    on E:Exception do
      ReportException('SetConfig', E);
  end;
end; { TDelphiLensUIWorker.SetConfig }

procedure TDelphiLensUIWorker.TimerRescan;
var
  msg: TOmniMessage;
begin
  msg := TOmniMessage.Create(0, TOmniValue.Null);
  Rescan(msg);
end; { TDelphiLensUIWorker.TimerRecan }

{ TDLUINavigationInfo }

constructor TDLUINavigationInfo.Create(const location: TDLUIXLocation);
begin
  FileNameStr := location.FileName;
  UniqueString(FileNameStr);
  FileName := PChar(FileNameStr);
  Line := location.Line;
  Column := location.Column;
end; { TDLUINavigationInfo.Create }

initialization
  GLogHook := nil;
end.
