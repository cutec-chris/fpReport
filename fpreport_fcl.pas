{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit fpreport_fcl;

interface

uses
  FPFontTextMapping, fpparsettf, fpPDF, fpTTF, fpttfencodings, fpTTFSubsetter, 
  fpExtFuncs, fpjsonreport, fprepexprpars, fpreport, fpreportbarcode, 
  fpreportcanvashelper, fpreportcontnr, fpreportdb, fpreportdom, 
  fpreportfpimageexport, fpreporthtmlexport, fprephtmlparser, 
  fpreporthtmlutil, fpreportjson, fpreportpdfexport, fpreportqrcode, 
  fpRepStreamer, fpimgbarcode, nr_intrp, nr_pars, nr_const, fprepdata, 
  LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('fpreport_fcl', @Register);
end.
