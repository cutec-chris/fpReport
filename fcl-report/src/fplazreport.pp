{
    This file is part of the Free Component Library.
    Copyright (c) 2017 Michael Van Canneyt, member of the Free Pascal development team

    TFPReport descendent that stores it's design in a JSON structure. 
    Can be used in an IDE

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit fplazreport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpreport, fpjsonreport, DOM, XMLRead,
  FPReadPNG,FPimage,FPCanvas,fpreportdb;

Type
  TCustomPropEvent = procedure(Sender: TObject;Data : TDOMNode) of object;

  { TFPLazReport }

  TFPLazReport = class(TFPJSONReport)
  private
    FData: TComponent;
    FMemoClass: TFPReportElementClass;
    FOnSetCustomProps: TCustomPropEvent;
  Protected
  Public
    constructor Create(AOwner: TComponent); override;
    function FixDataFields(aFieldName : string;RemoveBrackets : Boolean = False) : string;
    property MemoClass : TFPReportElementClass read FMemoClass write FmemoClass;
    Procedure LoadFromXML(LazReport : TXMLDocument); virtual;
    Procedure LoadFromFile(const aFileName : String);override;
    property DataContainer : TComponent read FData write FData;
    property OnSetCustomproperties : TCustomPropEvent read FOnSetCustomProps write FOnSetCustomProps;
  end;

  function MMToPixels(Const Dist: double) : Integer;
  function PixelsToMM(Const Dist: double) : TFPReportUnits;

implementation

uses fpTTF,dateutils,base64,FPReadGif,FPReadJPEG,fpexprpars;

function PixelsToMM(Const Dist: double) : TFPReportUnits;
begin
  Result:=Dist*(1/3.76);
end;
function MMToPixels(Const Dist: double) : Integer;
begin
  Result:=round(Dist*(3.76));
end;

function PageToMM(Const Dist: double) : TFPReportUnits;
begin
  Result:=Dist*(1/2.83);
end;

{ TFPLazReport }

constructor TFPLazReport.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  MemoClass := TFPReportMemo;
  FData := Owner;
end;

function TFPLazReport.FixDataFields(aFieldName: string; RemoveBrackets: Boolean
  ): string;
var
  k : Integer = 0;
  atmp : string;
  tmp: String;
  tmp1: String;
begin
  Result := aFieldName;
  if Assigned(FData) then
    while k < FData.ComponentCount do
      begin
        if FData.Components[k] is TFPReportDatasetData then
          Result := StringReplace(Result,TFPReportDatasetData(FData.Components[k]).Name+'.',TFPReportDatasetData(FData.Components[k]).Name+'.',[rfReplaceAll,rfIgnoreCase]);
        inc(k);
      end;
  Result := StringReplace(Result,'PAGE#','PageNo',[rfReplaceAll,rfIgnoreCase]);
  Result := StringReplace(Result,'[DATE]','[TODAY]',[rfReplaceAll,rfIgnoreCase]);
  if RemoveBrackets then
    begin
      Result := StringReplace(Result,'[','',[rfReplaceAll,rfIgnoreCase]);
      Result := StringReplace(Result,']','',[rfReplaceAll,rfIgnoreCase]);
    end;
  if pos('sum(',lowercase(Result))>0 then
    begin
      tmp := copy(Result,0,pos('sum(',lowercase(Result))+3);
      Result := copy(Result,pos('sum(',lowercase(Result))+4,length(Result));
      if (pos(',',Result)>0) and (pos(',',Result)<pos(')',Result)) then
        begin
          tmp := tmp+copy(Result,0,pos(',',Result)-1);
          Result := copy(Result,pos(')',Result),length(Result));
        end;
      tmp := tmp+Result;
      Result := tmp;
    end;
  while pos('([',Result)>0 do
    begin
      tmp := copy(Result,0,pos('([',Result)-1)+'(';
      Result := copy(Result,pos('([',Result)+2,length(Result));
      tmp += copy(Result,0,pos(']',Result)-1);
      Result := copy(Result,pos(']',Result)+1,length(Result));
      tmp += Result;
      Result := tmp;
    end;
  if pos('[',Result)>0 then
    begin
      tmp := copy(Result,pos('[',Result)+1,length(Result));
      if (pos('[',tmp)>0) and (pos('[',tmp)<pos(']',tmp)) then
        begin
          tmp := copy(Result,0,pos('[',Result)-1);
          Result := copy(Result,pos('[',Result)+1,length(Result));
          tmp1 := '';
          while pos(']',Result)>0 do
            begin
              tmp1 += copy(Result,0,pos(']',result)-1);
              Result := copy(Result,pos(']',result)+1,length(Result));
            end;
          tmp+=StringReplace(tmp1,'[','',[rfReplaceAll]);
          tmp+=Result;
        end;
    end;
end;

procedure TFPLazReport.LoadFromXML(LazReport: TXMLDocument);
var
  lPages: TDOMNode;
  aPage: TFPReportPage;
  Config: TDOMNode;
  BaseNode: TDOMNode;
  nPage: TDOMNode;
  aBand: TFPReportCustomBand;
  aObj: TFPReportElement;
  aDataNode: TDOMNode;
  tmp: String;
  ourBand: TFPReportCustomBand;
  OffsetTop: TFPReportUnits;
  OffsetLeft: TFPReportUnits;
  aData: TFPReportData;
  aFont: TFPFontCacheItem;
  aDetailHeader : TFPReportDataHeaderBand;
  aDetailFooter : TFPReportDataFooterBand;
  aMasterData: TFPReportDataBand;
  aDetailBand: TFPReportDataBand;
  HasFrame: Boolean;
  aBold: Boolean;
  aItalic: Boolean;
  aSize: Integer;
  ss: TStringStream;
  aReader: TFPCustomImageReader;
  fs: TFileStream;
  cd: integer;
  B: Byte;
  k: Integer;
  aColor: Integer;
  FontFound: Boolean;
  aFlag: Integer;
  i: Integer;
  j: Integer;
  function Blue(rgb: Integer): BYTE;
  begin
    Result := (rgb shr 16) and $000000ff;
  end;

  function Green(rgb: Integer): BYTE;
  begin
    Result := (rgb shr 8) and $000000ff;
  end;

  function Red(rgb: Integer): BYTE;
  begin
    Result := rgb and $000000ff;
  end;

  function GetProperty(aNode : TDOMNode;aName : string;aValue : string = 'Value') : string;
  var
    bNode: TDOMNode;
  begin
    Result := '';
    bNode := aNode.FindNode(aName);
    if Assigned(bNode) then
      if Assigned(bNode.Attributes.GetNamedItem(aValue)) then
        Result := bNode.Attributes.GetNamedItem(aValue).NodeValue;
  end;

  function FindBand(aPage : TFPReportPage;aTop : double) : TFPReportCustomBand;
  var
    b : Integer;
  begin
    Result := nil;
    for b := 0 to aPage.BandCount-1 do
      begin
        if (aTop>=aPage.Bands[b].Layout.Top)
        and (aTop<=aPage.Bands[b].Layout.Top+aPage.Bands[b].Layout.Height) then
          begin
            Result := aPage.Bands[b];
            break;
          end;
      end;
  end;

begin
  BaseNode := LazReport.DocumentElement.FindNode('LazReport');
  if not Assigned(BaseNode) then exit;
  lPages := BaseNode.FindNode('Pages');
  if Assigned(lPages) then
    begin
      TwoPass:= GetProperty(lPages,'DoublePass') = 'True';
      with lPages.ChildNodes do
        begin
          for i := 0 to (Count - 1) do
            if (copy(Item[i].NodeName,0,4)='Page') and (Item[i].NodeName<>'PageCount') then
              begin
                aMasterData := nil;
                aDetailBand := nil;
                aDetailHeader := nil;
                aDetailFooter := nil;
                aData := nil;
                aPage := TFPReportPage.Create(Self);
                aPage.PageSize.PaperName:='A4';
                aPage.Font.Name:='ArialMT';
                if GetProperty(Item[i],'Width')<>'' then
                  aPage.PageSize.Width := round(PageToMM(StrToFloatDef(GetProperty(Item[i],'Width'),aPage.PageSize.Width)));
                if GetProperty(Item[i],'Height')<>'' then
                  aPage.PageSize.Height := round(PageToMM(StrToFloatDef(GetProperty(Item[i],'Height'),aPage.PageSize.Width)));
                aDataNode := Item[i].FindNode('Margins');
                if Assigned(aDataNode) then
                  begin
                    aPage.Margins.Top:=PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Top'),aPage.Margins.Top));
                    aPage.Margins.Left:=PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'left'),aPage.Margins.Left));
                    aPage.Margins.Right:=PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Right'),aPage.Margins.Right));
                    aPage.Margins.Bottom:=PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Bottom'),aPage.Margins.Bottom));
                  end;
                nPage := Item[i];
                for j := 0 to nPage.ChildNodes.Count-1 do
                  if copy(nPage.ChildNodes.Item[j].NodeName,0,6)='Object' then
                    begin
                      aObj := nil;
                      ourBand := nil;
                      case GetProperty(nPage.ChildNodes.Item[j],'ClassName') of
                      'TfrBandView':
                        begin
                          tmp := GetProperty(nPage.ChildNodes.Item[j],'BandType');
                          case tmp of
                          'btReportTitle':aBand := TFPReportTitleBand.Create(aPage);
                          'btMasterData':
                            begin
                              aBand := TFPReportDataBand.Create(aPage);
                              tmp := GetProperty(nPage.ChildNodes.Item[j],'DatasetStr');
                              if copy(tmp,1,1)='P' then
                                tmp := copy(tmp,2,system.length(tmp));
                              if Assigned(FData) then
                                aData := TFPreportData(FData.FindComponent(tmp));
                              if Assigned(aData) then
                                begin
                                  aPage.Data := aData;
                                  TFPReportDataBand(aBand).Data := aData;
                                end;
                              aMasterData := TFPReportDataBand(aBand);
                            end;
                          'btMasterHeader':
                            begin
                              aBand := TFPReportDataHeaderBand.Create(aPage);
                            end;
                          'btMasterFooter':
                            begin
                              aBand := TFPReportDataFooterBand.Create(aPage);
                            end;
                          'btDetailData':
                            begin
                              aBand := TFPReportDataBand.Create(aPage);
                              tmp := GetProperty(nPage.ChildNodes.Item[j],'DatasetStr');
                              if copy(tmp,1,1)='P' then
                                tmp := copy(tmp,2,system.length(tmp));
                              if Assigned(FData) and (FData.FindComponent(tmp) <> nil) then
                                TFPReportDataBand(aBand).Data := TFPreportData(FData.FindComponent(tmp));
                              TFPReportDataBand(aBand).MasterBand := aMasterData;
                              aDetailBand := TFPReportDataBand(aBand);
                              if Assigned(aDetailHeader) then
                                begin
                                  aDetailHeader.Data := TFPReportDataBand(aBand).Data;
                                  aDetailHeader := nil;
                                end;
                              if Assigned(aDetailFooter) then
                                begin
                                  aDetailFooter.Data := TFPReportDataBand(aBand).Data;
                                  aDetailFooter := nil;
                                end;
                            end;
                          'btDetailHeader':
                            begin
                              aBand := TFPReportDataHeaderBand.Create(aPage);
                              if Assigned(aDetailBand) then
                                begin
                                  TFPReportDataHeaderBand(aBand).Data := aDetailBand.Data;
                                end
                              else aDetailHeader := TFPReportDataHeaderBand(aBand);
                            end;
                          'btDetailFooter':
                            begin
                              aBand := TFPReportDataFooterBand.Create(aPage);
                              if Assigned(aDetailBand) then
                                begin
                                  TFPReportDataFooterBand(aBand).Data := aDetailBand.Data;
                                end
                              else aDetailFooter := TFPReportDataFooterBand(aBand);
                            end;
                          'btPageHeader':aBand := TFPReportPageHeaderBand.Create(aPage);
                          'btPageFooter':aBand := TFPReportPageFooterBand.Create(aPage);
                          'btGroupHeader':
                            begin
                              aBand := TFPReportGroupHeaderBand.Create(aPage);
                              tmp := GetProperty(nPage.ChildNodes.Item[j],'Condition');
                              if copy(tmp,0,1)='[' then
                                tmp := copy(tmp,2,system.length(tmp)-2);//remove []
                              tmp := FixDataFields(tmp,True);
                              TFPReportGroupHeaderBand(aBand).GroupCondition:=tmp;
                              tmp := GetProperty(nPage.ChildNodes.Item[j],'Condition');
                              if pos('(',tmp)>0 then
                                begin
                                  tmp := copy(tmp,pos('(',tmp)+1,system.length(tmp));
                                  tmp := copy(tmp,0,pos(')',tmp)-1);
                                end;
                              if copy(tmp,0,1)='[' then
                                tmp := copy(tmp,2,system.length(tmp)-2);//remove []
                              if copy(tmp,1,1)='P' then
                                tmp := copy(tmp,2,system.length(tmp));
                              if pos('.',tmp)>0 then tmp := copy(tmp,0,pos('.',tmp)-1);
                              if Assigned(FData) and (FData.FindComponent(tmp) <> nil) then
                                TFPReportGroupHeaderBand(aBand).Data := TFPreportData(FData.FindComponent(tmp));
                            end;
                          'btGroupFooter':aBand := TFPReportGroupFooterBand.Create(aPage);
                          else
                            aBand := TFPReportCustomBand.Create(aPage);
                          end;
                          if Assigned(aBand) then
                            TFPReportDataBand(aBand).StretchMode:=smActualHeight;
                          aObj := aBand;
                        end;
                      'TfrMemoView':
                        begin
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Size');
                          ourBand := FindBand(aPage,PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Top'),0)));
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Data');
                          aObj := MemoClass.Create(ourBand);
                          if Assigned(FOnSetCustomProps) then
                            FOnSetCustomProps(aObj,aDataNode);
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Size');
                          case GetProperty(nPage.ChildNodes.Item[j],'Alignment') of
                          'taRightJustify':TFPReportMemo(aObj).TextAlignment.Horizontal:=taRightJustified;
                          'taCenter':TFPReportMemo(aObj).TextAlignment.Horizontal:=taCentered;
                          end;
                          case GetProperty(nPage.ChildNodes.Item[j],'Layout') of
                          'tlCenter':TFPReportMemo(aObj).TextAlignment.Vertical:=TFPReportVertTextAlignment.tlCenter;
                          'tlTop':TFPReportMemo(aObj).TextAlignment.Vertical:=TFPReportVertTextAlignment.tlTop;
                          'tlBottom':TFPReportMemo(aObj).TextAlignment.Vertical:=TFPReportVertTextAlignment.tlBottom;
                          end;
                          TFPReportMemo(aObj).StretchMode:=smActualHeight;
                          aFlag := StrToIntDef(GetProperty(nPage.ChildNodes.Item[j],'Flags'),0);
                          if aFlag and 3 = 3 then
                            TFPReportMemo(aObj).StretchMode:=smMaxHeight;
                          TFPReportMemo(aObj).TextAlignment.TopMargin:=1;
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Data');
                          TFPReportMemo(aObj).Text:=FixDataFields(GetProperty(aDataNode,'Memo'));
                          TFPReportMemo(aObj).UseParentFont := False;
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Font');
                          aBold := pos('fsBold',GetProperty(aDataNode,'Style'))>0;
                          aItalic := pos('fsItalic',GetProperty(aDataNode,'Style'))>0;
                          aFont := gTTFontCache.Find(GetProperty(aDataNode,'Name'),aBold,aItalic);
                          FontFound := not Assigned(aFont);
                          if not Assigned(aFont) then
                            aFont := gTTFontCache.Find('LiberationSans',aBold,aItalic);
                          if not Assigned(aFont) then
                            aFont := gTTFontCache.Find('Arial',aBold,aItalic);
                          if not Assigned(aFont) then
                            aFont := gTTFontCache.Find('DejaVu',aBold,aItalic);
                          if not Assigned(aFont) then
                            begin
                              with gTTFontCache do
                                for b := 0 to Count-1 do
                                  begin
                                    if (pos('sans',lowercase(Items[b].FamilyName)) > 0) and (Items[b].IsItalic = AItalic)
                                        and (Items[b].IsBold = ABold)
                                    then
                                      begin
                                        aFont := Items[b];
                                        break;
                                      end;
                                  end;
                            end;
                          {$ifdef UNIX}
                          if (not FontFound) and Assigned(aFont) then
                            writeln('using Font "'+aFont.FamilyName+'" instead "'+GetProperty(aDataNode,'Name')+'"');
                          {$endif}
                          if Assigned(aFont) then
                            TFPReportMemo(aObj).Font.Name:=aFont.PostScriptName
                          else TFPReportMemo(aObj).UseParentFont := true;
                          aSize := StrToIntDef(GetProperty(aDataNode,'Size'),TFPReportMemo(aObj).Font.Size);
                          if aSize>5 then dec(aSize);
                          TFPReportMemo(aObj).Font.Size:=aSize;
                          aColor := StrToIntDef(GetProperty(aDataNode,'Color'),0);
                          TFPReportMemo(aObj).Font.Color:= RGBToReportColor(Red(aColor),Green(aColor),Blue(aColor));
                        end;
                      'TfrLineView':
                        begin
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Size');
                          ourBand := FindBand(aPage,PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Top'),0)));
                          aObj := TFPReportShape.Create(ourBand);
                          TFPReportShape(aObj).ShapeType:=stLine;
                          TFPReportShape(aObj).Orientation:=orEast;
                        end;
                      'TfrPictureView':
                        begin
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Size');
                          ourBand := FindBand(aPage,PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Top'),0)));
                          aObj := TFPReportImage.Create(ourBand);
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Picture');
                          aReader:=nil;
                          case lowercase(GetProperty(aDataNode,'Type','Ext')) of
                          'jpeg','jpg':aReader := TFPReaderJPEG.Create;
                          'png':aReader := TFPReaderPNG.create;
                          'gif':aReader := TFPReaderGif.Create;
                          end;
                          if Assigned(aReader) then
                            begin
                              tmp := GetProperty(aDataNode,'Data');
                              ss := TStringStream.Create('');
                              if tmp<>'' then
                                for k:=1 to (system.length(tmp) div 2) do begin
                                  Val('$'+tmp[k*2-1]+tmp[k*2], B, cd);
                                  ss.Write(B, 1);
                                end;
                              ss.Position:=0;
                              fs := TFileStream.Create(GetTempDir+'repimage.'+GetProperty(aDataNode,'Type','Ext'),fmCreate);
                              fs.CopyFrom(ss,0);
                              fs.Free;
                              TFPReportImage(aObj).LoadFromFile(GetTempDir+'repimage.'+GetProperty(aDataNode,'Type','Ext'));
                              TFPReportImage(aObj).Stretched:=True;
                              DeleteFile(GetTempDir+'repimage.'+GetProperty(aDataNode,'Type','Ext'));
                              ss.Free;
                            end;
                          aReader.Free;
                        end;
                      end;
                      if Assigned(aObj) and (aObj is TFPReportElement) then
                        begin
                          TFPReportElement(aObj).Name:=GetProperty(nPage.ChildNodes.Item[j],'Name');
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Size');
                          if Assigned(aDataNode) then
                            begin
                              if Assigned(ourBand) then
                                OffsetTop := ourBand.Layout.Top
                              else OffsetTop := 0;
                              OffsetLeft :=0;
                              if not (aObj is TFPReportCustomBand) then
                                OffsetLeft := aPage.Margins.Left;
                              TFPReportElement(aObj).Layout.Top:=PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Top'),TFPReportElement(aObj).Layout.Top))-OffsetTop;
                              TFPReportElement(aObj).Layout.Left:=PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Left'),TFPReportElement(aObj).Layout.Left))-OffsetLeft;
                              TFPReportElement(aObj).Layout.Width:=PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Width'),TFPReportElement(aObj).Layout.Width));
                              TFPReportElement(aObj).Layout.Height:=PixelsToMM(StrToFloatDef(GetProperty(aDataNode,'Height'),TFPReportElement(aObj).Layout.Height));
                            end;
                          HasFrame:=False;
                          aDataNode := nPage.ChildNodes.Item[j].FindNode('Frames');
                          if Assigned(aDataNode) then
                            begin
                              TFPReportElement(aObj).Frame.Shape:=fsNone;
                              if GetProperty(aDataNode,'FrameColor')<>'' then
                                begin
                                  aColor := StrToIntDef(GetProperty(aDataNode,'FrameColor'),0);
                                  TFPReportElement(aObj).Frame.Color:= RGBToReportColor(Red(aColor),Green(aColor),Blue(aColor));
                                end;
                              TFPReportElement(aObj).Frame.Width := StrToIntDef(GetProperty(aDataNode,'FrameWidth'),0);
                              TFPReportElement(aObj).Frame.Lines:=[];
                              tmp := GetProperty(aDataNode,'FrameBorders');
                              if tmp <> '' then
                                begin
                                  if pos('frbBottom',tmp)>0 then
                                    TFPReportElement(aObj).Frame.Lines := TFPReportElement(aObj).Frame.Lines+[flBottom];
                                  if pos('frbTop',tmp)>0 then
                                    TFPReportElement(aObj).Frame.Lines := TFPReportElement(aObj).Frame.Lines+[flTop];
                                  if pos('frbLeft',tmp)>0 then
                                    TFPReportElement(aObj).Frame.Lines := TFPReportElement(aObj).Frame.Lines+[flLeft];
                                  if pos('frbRight',tmp)>0 then
                                    TFPReportElement(aObj).Frame.Lines := TFPReportElement(aObj).Frame.Lines+[flRight];
                                  HasFrame := TFPReportElement(aObj).Frame.Lines<>[];
                                end;
                            end;
                          if (aObj is TFPReportMemo)
                          and (GetProperty(nPage.ChildNodes.Item[j],'FillColor')<>'clNone')
                          and (GetProperty(nPage.ChildNodes.Item[j],'FillColor')<>'') then
                            begin
                              aColor := StrToIntDef(GetProperty(nPage.ChildNodes.Item[j],'FillColor'),0);
                              TFPReportMemo(aObj).Frame.Pen:=psClear;
                              TFPReportMemo(aObj).Frame.BackgroundColor:= RGBToReportColor(Red(aColor),Green(aColor),Blue(aColor));
                              TFPReportMemo(aObj).Frame.Shape:=fsRectangle;
                              if not HasFrame then
                                begin
                                  TFPReportMemo(aObj).Frame.Color:=RGBToReportColor(Red(aColor),Green(aColor),Blue(aColor));
                                  TFPReportMemo(aObj).Frame.Pen:=psClear;
                                end;
                            end;
                        end;
                    end;
                AddPage(aPage);
              end;
        end;
    end;
end;

procedure TFPLazReport.LoadFromFile(const aFileName: String);
var
  LazReport: TXMLDocument;
begin
  if lowercase(ExtractFileExt(aFileName)) = '.lrf' then
    begin
      ReadXMLFile(LazReport, aFileName);
      LoadFromXML(LazReport);
      LazReport.Free;
    end
  else inherited;
end;

Procedure BuiltinIFS(Var Result : TFPExpressionResult; Const Args : TExprParameterArray);

begin
  If Args[0].resBoolean then
    Result.resString:=Args[1].resString
  else
    Result.resString:=Args[2].resString
end;

initialization
  BuiltinIdentifiers.AddFunction(bcBoolean,'IF','S','BSS',@BuiltinIFS);
end.

