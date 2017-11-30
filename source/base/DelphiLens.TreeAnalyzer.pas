unit DelphiLens.TreeAnalyzer;

interface

uses
  DelphiLens.TreeAnalyzer.Intf;

function CreateDLTreeAnalyzer: IDLTreeAnalyzer;

implementation

uses
  Spring, Spring.Collections,
  GpStuff,
  DelphiAST.Consts, DelphiAST.Classes,
  DelphiLens.DelphiASTHelpers, DelphiLens.UnitInfo;

type
  TDLTreeAnalyzer = class(TInterfacedObject, IDLTreeAnalyzer)
  strict private
    FNodeToSection: array [TSyntaxNodeType] of TDLTypeSection;
  strict protected
    procedure GetUnitList(usesNode: TSyntaxNode; var units: TDLUnitList);
    function  ParseTypes(node: TSyntaxNode): IList<TDLTypeInfo>;
  public
    constructor Create;
    procedure AnalyzeTree(tree: TSyntaxNode; var unitInfo: IDLUnitInfo);
  end; { TDLTreeAnalyzer }

{ exports }

function CreateDLTreeAnalyzer: IDLTreeAnalyzer;
begin
  Result := TDLTreeAnalyzer.Create;
end; { CreateDLTreeAnalyzer }

{ TDLTreeAnalyzer }

constructor TDLTreeAnalyzer.Create;
begin
  inherited Create;
  FillChar(FNodeToSection, SizeOf(FNodeToSection), $FF);
  FNodeToSection[ntStrictPrivate]   := secStrictPrivate;
  FNodeToSection[ntPrivate]         := secPrivate;
  FNodeToSection[ntStrictProtected] := secStrictProtected;
  FNodeToSection[ntProtected]       := secProtected;
  FNodeToSection[ntPublic]          := secPublic;
  FNodeToSection[ntPublished]       := secPublished;
end; { TDLTreeAnalyzer.Create }

procedure TDLTreeAnalyzer.AnalyzeTree(tree: TSyntaxNode; var unitInfo: IDLUnitInfo);
var
  ndContains: TSyntaxNode;
  ndImpl    : TSyntaxNode;
  ndIntf    : TSyntaxNode;
  ndUnit    : TSyntaxNode;
  ndUses    : TSyntaxNode;
  units: TDLUnitList;
begin
  unitInfo := CreateDLUnitInfo;
  if not tree.FindFirst(ntUnit, ndUnit) then
    Exit;

  unitInfo.Name := ndUnit.GetAttribute(anName);

  ndIntf := ndUnit.FindFirst(ntInterface);
  if assigned(ndIntf) then begin
    ndImpl := ndUnit.FindFirst(ntImplementation);
    unitInfo.InterfaceLoc := TDLCoordinate.Create(ndIntf);
    unitInfo.ImplementationLoc := TDLCoordinate.Create(ndImpl);
  end
  else begin
    ndIntf := ndUnit; //alias to simplify .dpr parsing
    ndImpl := nil;
  end;

  unitInfo.InitializationLoc := TDLCoordinate.Create(ndUnit.FindFirst(ntInitialization));
  unitInfo.FinalizationLoc := TDLCoordinate.Create(ndUnit.FindFirst(ntFinalization));

  ndUses := ndIntf.FindFirst(ntUses);
  if assigned(ndUses) then begin
    GetUnitList(ndUses, units);
    unitInfo.InterfaceUses := units;
    unitInfo.InterfaceUsesLoc := TDLCoordinate.Create(ndUses);
  end;

  ndContains := ndIntf.FindFirst(ntContains);
  if assigned(ndContains) then begin
    GetUnitList(ndContains, units);
    unitInfo.PackageContains := units;
    unitInfo.ContainsLoc := TDLCoordinate.Create(ndContains);
  end;

  if assigned(ndImpl) then begin
    ndUses := ndImpl.FindFirst(ntUses);
    if assigned(ndUses) then begin
      GetUnitList(ndUses, units);
      unitInfo.ImplementationUses := units;
      unitInfo.ImplementationUsesLoc := TDLCoordinate.Create(ndUses);
    end;
  end;

  unitInfo.InterfaceTypes := ParseTypes(ndIntf);
  if assigned(ndImpl) then
    unitInfo.ImplementationTypes := ParseTypes(ndImpl);
end; { TDLTreeAnalyzer.AnalyzeTree }

procedure TDLTreeAnalyzer.GetUnitList(usesNode: TSyntaxNode; var units: TDLUnitList);
var
  childNode: TSyntaxNode;
begin
  for childNode in usesNode.ChildNodes do
    if childNode.Typ = ntUnit then
      units.Add(childNode.GetAttribute(anName));
end; { TDLTreeAnalyzer.GetUnitList }

function TDLTreeAnalyzer.ParseTypes(node: TSyntaxNode): IList<TDLTypeInfo>;
var
  nodeSection : TSyntaxNode;
  nodeType    : TSyntaxNode;
  nodeTypeDecl: TSyntaxNode;
  nodeTypeSect: TSyntaxNode;
  typeInfo    : TDLTypeInfo;
begin
  Result := TCollections.CreateObjectList<TDLTypeInfo>;
  for nodeTypeSect in node.FindAll(ntTypeSection, false) do begin
    for nodeTypeDecl in nodeTypeSect.FindAll(ntTypeDecl) do begin
      typeInfo := TDLTypeInfo.Create;
      typeInfo.Location := TDLCoordinate.Create(nodeTypeDecl);
      if nodeTypeDecl.FindFirst(ntType, nodeType) then begin
        for nodeSection in nodeType.FindAll([ntStrictPrivate, ntPrivate, ntStrictProtected,
                                             ntProtected, ntPublic, ntPublished]) do
        begin
          typeInfo.EnsureSection(FNodeToSection[nodeSection.Typ]).Location := TDLCoordinate.Create(nodeSection);
          // TODO 1 -oPrimoz Gabrijelcic : Parse subtypes
        end;
      end;
      Result.Add(typeInfo);
    end;
  end;
end; { TDLTreeAnalyzer.ParseTypes }

end.
