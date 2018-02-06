{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit lazfpreportdesign;

interface

uses
  fpreportdesignreportdata, fpreportdrawruler, fpreportdesignctrl, 
  fpreportdesignobjectlist, frafpreportdbfdata, frafpreportjsondata, 
  frafpreportdata, fraReportObjectInspector, frafpreportsqldbdata, 
  frmfpreportalignelements, frmconfigreportdata, 
  frmfpreportdataconnectioneditor, frmfpreportdesignermain, 
  frmfpreportimageedit, frmfpreportmemoedit, frmfpreportpreviewdata, 
  frmfpreportproperties, frmfpreportshapeedit, frmfpreportvariables, 
  frmfprdresizeelements, regfpdesigner, FPReportDesigner, LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('lazfpreportdesign', @Register);
end.
