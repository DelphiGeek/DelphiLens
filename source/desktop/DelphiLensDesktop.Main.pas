unit DelphiLensDesktop.Main;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Variants, System.Classes, System.Actions,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ActnList, Vcl.Samples.Spin,
  Spring.Collections,
  DelphiAST.Classes,
  DelphiLens.DelphiASTHelpers,
  DelphiLens.Intf, DelphiLens.UnitInfo, Vcl.Buttons;

type
  TfrmDLMain = class(TForm)
    actAnalysis      : TAction;
    actFindSyntaxNode: TAction;
    actIncludeFiles  : TAction;
    ActionList       : TActionList;
    actNotFound      : TAction;
    actParsedUnits   : TAction;
    actProblems      : TAction;
    btnAnalysis      : TButton;
    btnFindNode      : TButton;
    btnIncludeFiles  : TButton;
    btnNotFound      : TButton;
    btnParsedUnits   : TButton;
    btnProblems      : TButton;
    btnRescan        : TButton;
    btnSelect        : TButton;
    dlgOpenProject   : TFileOpenDialog;
    inpCol           : TSpinEdit;
    inpDefines       : TEdit;
    inpLine          : TSpinEdit;
    inpProject       : TEdit;
    inpSearchPath    : TEdit;
    lbFiles          : TListBox;
    lblCol           : TLabel;
    lblDefines       : TLabel;
    lblLine          : TLabel;
    lblProject       : TLabel;
    lblSearchPath    : TLabel;
    lblWhatIsShowing : TLabel;
    outLog           : TMemo;
    lblNodeName      : TLabel;
    btnTestForm      : TBitBtn;
    procedure actAnalysisExecute(Sender: TObject);
    procedure actFindSyntaxNodeExecute(Sender: TObject);
    procedure actFindSyntaxNodeUpdate(Sender: TObject);
    procedure actIncludeFilesExecute(Sender: TObject);
    procedure actNotFoundExecute(Sender: TObject);
    procedure actParsedUnitsExecute(Sender: TObject);
    procedure actProblemsExecute(Sender: TObject);
    procedure btnRescanClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnSelectClick(Sender: TObject);
    procedure EnableResultActions(Sender: TObject);
    procedure inpProjectChange(Sender: TObject);
    procedure lbFilesClick(Sender: TObject);
    procedure SettingExit(Sender: TObject);
    procedure btnTestFormClick(Sender: TObject);
  private const
    CSettingsKey = '\SOFTWARE\Gp\DelphiLens\DelphiLensDesktop';
    CSettingsProject            = 'Project';
    CSettingsSearchPath         = 'SearchPath';
    CSettingsConditionalDefines = 'ConditionalDefines';
  type
    TShowing = (shAnalysis, shParsedUnits, shIncludeFiles, shNotFound, shProblems);
  var
    FDelphiLens: IDelphiLens;
    FLoading   : boolean;
    FOpenCache : boolean;
    FScanResult: IDLScanResult;
    FShowing   : TShowing;
  strict protected
    function  AttributestoStr(const attributes: TArray<TAttributeEntry>): string;
    procedure DumpAnalysis(log: TStrings; const unitInfo: IDLUnitInfo);
    procedure DumpClasses(log: TStrings; const typeList: TDLTypeInfoList);
    procedure DumpSyntaxTree(log: TStrings; node: TSyntaxNode; const prefix: string);
    procedure DumpUses(log: TStrings; const usesList: TDLUnitList;
      const location: TDLCoordinate);
    procedure LoadSettings;
    procedure SaveSettings;
    procedure ShowAnalysis;
    procedure ShowIncludeFiles;
    procedure ShowMissingFiles;
    procedure ShowParsedUnits;
    procedure ShowProblems;
    procedure TryToFocus(node: TSyntaxNode);
  public
  end;

var
  frmDLMain: TfrmDLMain;

implementation

uses
  System.RTTI,
  DSiWin32,
  GpStuff, GpVCL,
  DelphiAST.Consts, DelphiAST.ProjectIndexer,
  DelphiLens,
  DelphiLensDesktop.Test;

{$R *.dfm}

procedure TfrmDLMain.actAnalysisExecute(Sender: TObject);
begin
  ShowAnalysis;
end;

procedure TfrmDLMain.actFindSyntaxNodeExecute(Sender: TObject);
var
  node: TSyntaxNode;
  unitInfo: TProjectIndexer.TUnitInfo;
begin
  if not FScanResult.ParsedUnits.Find(lbFiles.Items[lbFiles.ItemIndex], unitInfo) then
    Exit;

  node := unitInfo.SyntaxTree.FindLocation(inpLine.Value, inpCol.Value);
  if not assigned(node) then
    MessageBeep($FFFFFFFF)
  else begin
    TryToFocus(node);
    node := node.FindParentWithName;
    if not assigned(node) then
      lblNodeName.Visible := false
    else begin
      lblNodeName.Caption := node.GetAttribute(anName);
      lblNodeName.Visible := true;
    end;
  end;
end;

procedure TfrmDLMain.actFindSyntaxNodeUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := (FShowing = shParsedUnits);
end;

procedure TfrmDLMain.actIncludeFilesExecute(Sender: TObject);
begin
  ShowIncludeFiles;
end;

procedure TfrmDLMain.actNotFoundExecute(Sender: TObject);
begin
  ShowMissingFiles;
end;

procedure TfrmDLMain.actParsedUnitsExecute(Sender: TObject);
begin
  ShowParsedUnits;
end;

procedure TfrmDLMain.actProblemsExecute(Sender: TObject);
begin
  ShowProblems;
end;

function TfrmDLMain.AttributestoStr(const attributes: TArray<TAttributeEntry>): string;
var
  i: integer;
begin
  Result := '';
  if Length(attributes) > 0 then begin
    Result := '[';
    for i := Low(attributes) to High(attributes) do begin
      if i > Low(attributes) then
        Result := Result + ',';
      Result := Result + TRttiEnumerationType.GetName<TAttributeName>(attributes[i].Key) + '=' + attributes[i].Value;
    end;
    Result := Result + ']';
  end;
end;

procedure TfrmDLMain.btnRescanClick(Sender: TObject);
begin
  FScanResult := nil;
  if not assigned(FDelphiLens) then
    FDelphiLens := CreateDelphiLens(inpProject.Text);
  if FOpenCache then
    inpDefines.Text := FDelphiLens.ConditionalDefines;
  FDelphiLens.SearchPath := inpSearchPath.Text;
  FDelphiLens.ConditionalDefines := inpDefines.Text;
  with AutoRestoreCursor(crHourGlass) do begin
    FScanResult := FDelphiLens.Rescan;
    outLog.Text := Format(
      'Indexer'#13#10 +
      '  Parsed units: %d'#13#10 +
      '  Include files: %d'#13#10 +
      '  Not found: %d'#13#10 +
      '  Problems: %d'#13#10 +
      'Cache'#13#10 +
      '  Scanned: %d'#13#10 +
      '  Cached: %d',
      [FScanResult.ParsedUnits.Count, FScanResult.IncludeFiles.Count,
       FScanResult.NotFoundUnits.Count, FScanResult.Problems.Count,
      FScanResult.CacheStatistics.NumScanned, FScanResult.CacheStatistics.NumCached]);
    ShowAnalysis;
  end;
end;

procedure TfrmDLMain.FormCreate(Sender: TObject);
begin
  lblWhatIsShowing.Caption := '';
  LoadSettings;
end;

procedure TfrmDLMain.btnSelectClick(Sender: TObject);
begin
  if dlgOpenProject.Execute then begin
    inpProject.Text := dlgOpenProject.FileName;

    FOpenCache := DSiFileExtensionIs(dlgOpenProject.FileName, '.dlens');
    if FOpenCache then begin
      inpProject.Text := ChangeFileExt(inpProject.Text, '.dpk');
      if not FileExists(inpProject.Text) then
        inpProject.Text := ChangeFileExt(inpProject.Text, '.dpr');
    end;

    FDelphiLens := nil;
  end;
end;

procedure TfrmDLMain.btnTestFormClick(Sender: TObject);
begin
  frmTest.ShowModal;
end;

procedure TfrmDLMain.DumpAnalysis(log: TStrings; const unitInfo: IDLUnitInfo);
var
  isProgram: boolean;
begin
  isProgram := (unitInfo.UnitType = utProgram);
  log.Add(IFF(isProgram, 'program ', 'unit ') + unitInfo.Name);
  if isProgram then
    DumpUses(log, unitInfo.InterfaceUses, unitInfo.Sections[sntInterfaceUses])
  else begin
    log.Add('Interface @ ' + unitInfo.Sections[sntInterface].ToString);
    DumpUses(log, unitInfo.InterfaceUses, unitInfo.Sections[sntInterfaceUses]);
    DumpClasses(log, unitInfo.InterfaceTypes);
    log.Add('Implementation @ ' + unitInfo.Sections[sntImplementation].ToString);
    DumpUses(log, unitInfo.ImplementationUses, unitInfo.Sections[sntImplementationUses]);
    DumpClasses(log, unitInfo.ImplementationTypes);
  end;
  if unitInfo.Sections[sntInitialization].IsValid then
    log.Add('Initialization @ ' + unitInfo.Sections[sntInitialization].ToString);
  if unitInfo.Sections[sntFinalization].IsValid then
    log.Add('Finalization @ ' + unitInfo.Sections[sntFinalization].ToString);
end;

procedure TfrmDLMain.DumpSyntaxTree(log: TStrings; node: TSyntaxNode; const prefix: string);
var
  children    : TArray<TSyntaxNode>;
  i           : integer;
  newPrefix   : string;
  nodePosition: string;
  sAttributes : string;
begin
  sAttributes := AttributestoStr(node.Attributes);
  if Node is TCompoundSyntaxNode then
    nodePosition := Format('%d,%d - %d,%d', [
             TCompoundSyntaxNode(Node).Line, TCompoundSyntaxNode(Node).Col,
             TCompoundSyntaxNode(Node).EndLine, TCompoundSyntaxNode(Node).EndCol])
  else
    nodePosition := Format('%d,%d', [node.Line, node.Col]);
  log.Add(Format('%s%s %s @%s',
    [prefix, node.TypeName, sAttributes, nodePosition]));
  newPrefix := prefix + '  ';
  children := node.ChildNodes;
  for i := Low(children) to High(children) do
    DumpSyntaxTree(log, children[i], newPrefix);
end;

procedure TfrmDLMain.DumpUses(log: TStrings; const usesList: TDLUnitList;
  const location: TDLCoordinate);
var
  unitName: string;
begin
  if not location.IsValid then
    Exit;

  log.Add('uses @ ' + location.ToString);
  for unitName in usesList do
    log.Add('  ' + unitName);
end;

procedure TfrmDLMain.DumpClasses(log: TStrings; const typeList: TDLTypeInfoList);
var
  typeInfo: TDLTypeInfo;
begin
  if typeList.Count = 0 then
    Exit;

  log.Add('type');
  for typeInfo in typeList do
    log.Add('  ' + typeInfo.Name + ' @ ' + typeInfo.Location.ToString);
end;

procedure TfrmDLMain.EnableResultActions(Sender: TObject);
begin
  (Sender as TAction).Enabled := assigned(FScanResult);
end;

procedure TfrmDLMain.inpProjectChange(Sender: TObject);
begin
  SaveSettings;
end;

procedure TfrmDLMain.lbFilesClick(Sender: TObject);
var
  dlUnitInfo: IDLUnitInfo;
  outSl     : TStringList;
  unitInfo  : TProjectIndexer.TUnitInfo;
begin
  if not (FShowing in [shAnalysis, shParsedUnits]) then
    Exit;

  outLog.Clear;
  outLog.Update;
  outSl := TStringList.Create;
  try
    Screen.Cursor := crHourGlass;
    try
      if (FShowing = shAnalysis)
         and FScanResult.Analysis.Find(lbFiles.Items[lbFiles.ItemIndex], dlUnitInfo)
      then
        DumpAnalysis(outSl, dlUnitInfo)
      else if FScanResult.ParsedUnits.Find(lbFiles.Items[lbFiles.ItemIndex], unitInfo) then
        DumpSyntaxTree(outSl, unitInfo.SyntaxTree, '');
      outLog.Text := outSl.Text;
    finally Screen.Cursor := crDefault; end;
  finally FreeAndNil(outSl); end;
end;

procedure TfrmDLMain.LoadSettings;
begin
  FLoading := true;
  inpProject.Text := DSiReadRegistry(CSettingsKey, CSettingsProject, '');
  inpSearchPath.Text := DSiReadRegistry(CSettingsKey, CSettingsSearchPath, '');
  inpDefines.Text := DSiReadRegistry(CSettingsKey, CSettingsConditionalDefines, '');
  FLoading := false;
end;

procedure TfrmDLMain.SaveSettings;
begin
  if FLoading then
    Exit;

  DSiWriteRegistry(CSettingsKey, CSettingsProject, inpProject.Text);
  DSiWriteRegistry(CSettingsKey, CSettingsSearchPath, inpSearchPath.Text);
  DSiWriteRegistry(CSettingsKey, CSettingsConditionalDefines, inpDefines.Text);
end;

procedure TfrmDLMain.SettingExit(Sender: TObject);
begin
  SaveSettings;
end;

procedure TfrmDLMain.ShowAnalysis;
var
  i: integer;
begin
  lblWhatIsShowing.Caption := 'Analysis';
  lbFiles.Clear;
  lbFiles.Items.BeginUpdate;
  try
    for i := 0 to FScanResult.Analysis.Count - 1 do
      lbFiles.Items.Add(FScanResult.Analysis[i].Name);
  finally lbFiles.Items.EndUpdate; end;
  FShowing := shAnalysis;
end;

procedure TfrmDLMain.ShowIncludeFiles;
var
  i: integer;
begin
  lblWhatIsShowing.Caption := 'Include files';
  lbFiles.Clear;
  lbFiles.Items.BeginUpdate;
  try
    for i := 0 to FScanResult.IncludeFiles.Count - 1 do
      lbFiles.Items.Add(FScanResult.IncludeFiles[i].Name);
  finally lbFiles.Items.EndUpdate; end;
  FShowing := shIncludeFiles;
end;

procedure TfrmDLMain.ShowMissingFiles;
var
  i: integer;
begin
  lblWhatIsShowing.Caption := 'Missing files';
  lbFiles.Clear;
  lbFiles.Items.BeginUpdate;
  try
    for i := 0 to FScanResult.NotFoundUnits.Count - 1 do
      lbFiles.Items.Add(FScanResult.NotFoundUnits[i]);
  finally lbFiles.Items.EndUpdate; end;
  FShowing := shParsedUnits;
end;

procedure TfrmDLMain.ShowParsedUnits;
var
  i: integer;
begin
  lblWhatIsShowing.Caption := 'Parsed units';
  lbFiles.Clear;
  lbFiles.Items.BeginUpdate;
  try
    for i := 0 to FScanResult.ParsedUnits.Count - 1 do
      lbFiles.Items.Add(FScanResult.ParsedUnits[i].Name);
  finally lbFiles.Items.EndUpdate; end;
  FShowing := shParsedUnits;
end;

procedure TfrmDLMain.ShowProblems;
var
  i: integer;
begin
  lblWhatIsShowing.Caption := 'Problems';
  lbFiles.Clear;
  outLog.Clear;
  for i := 0 to FScanResult.Problems.Count - 1 do
    outLog.Lines.Add(FScanResult.Problems[i].FileName + ': ' + FScanResult.Problems[i].Description);
  FShowing := shProblems;
end;

procedure TfrmDLMain.TryToFocus(node: TSyntaxNode);
var
  iLine: integer;
  loc: string;
begin
  if node is TCompoundSyntaxNode then
    loc := Format('@%d,%d - %d,%d', [
             TCompoundSyntaxNode(Node).Line, TCompoundSyntaxNode(Node).Col,
             TCompoundSyntaxNode(Node).EndLine, TCompoundSyntaxNode(Node).EndCol])
  else
    loc := Format('@%d,%d', [node.Line, node.Col]);

  for iLine := 0 to outLog.Lines.Count - 1 do
    if outLog.Lines[iLine].EndsWith(loc) and TrimLeft(outLog.Lines[iLine]).StartsWith(node.TypeName) then begin
      outLog.Perform(EM_LINESCROLL, 0, iLine - outLog.Perform(EM_GETFIRSTVISIBLELINE, 0, 0));
      Exit;
    end;

  // Should not happen
  ShowMessage('Internal error: Node not found in the list!');
end;

initialization
  // test
end.
