;+
; NAME:
;       PC_READ_VAR_TIME
;
; PURPOSE:
;       Read time of a given var.dat, or other VAR file.
;
;       Returns the time from a snapshot (var) file generated by Pencil Code.
;
; CATEGORY:
;       Pencil Code, File I/O
;
; CALLING SEQUENCE:
;       pc_read_var_time, time=time, varfile=varfile, datadir=datadir, /quiet
; KEYWORD PARAMETERS:
;    datadir: Specifies the root data directory. Default: './data'.  [string]
;    varfile: Name of the var file. Default: 'var.dat'.              [string]
;   allprocs: Load data from the allprocs directory.                 [integer]
;   /reduced: Load reduced collective varfiles.
;
;       time: Variable in which to return the loaded time.           [real]
;exit_status: Suppress fatal errors in favour of reporting the
;             error through exit_status/=0.
;
;     /quiet: Suppress any information messages and summary statistics.
;      /help: Display this usage information, and exit.
;
; EXAMPLES:
;       pc_read_var, time=t              ;; read time into variable t
;-
; MODIFICATION HISTORY:
;       $Id$
;       Written by: Antony J Mee (A.J.Mee@ncl.ac.uk), 27th November 2002
;
;
pro pc_read_var_time,                                                              $
    time=time, varfile=varfile_, allprocs=allprocs, datadir=datadir, param=param,  $
    procdim=procdim, ivar=ivar, swap_endian=swap_endian, f77=f77, reduced=reduced, $
    exit_status=exit_status, quiet=quiet, single=single, help=help

COMPILE_OPT IDL2,HIDDEN
;
; Use common block belonging to derivative routines etc. so we can
; set them up properly.
;
  common pc_precision, zero, one, precision, data_type, data_bytes, type_idl

  if (keyword_set(help)) then begin
    doc_library, 'pc_read_var_time'
    return
  endif
;
; Default settings.
;
  default, reduced, 0
  default, quiet, 0
  default, single, 0
  datadir = pc_get_datadir (datadir)
;
  if (arg_present(exit_status)) then exit_status=0
;
; Name and path of varfile to read.
;
  if (n_elements(ivar) eq 1) then begin
    default, varfile_, 'VAR'
    varfile = varfile_ + strcompress (string (ivar), /remove_all)
    if (file_test (datadir+'/allprocs/'+varfile[0]+'.h5')) then varfile += '.h5'
  endif else begin
    default_varfile = 'var.dat'
    if (file_test (datadir+'/allprocs/var.h5')) then default_varfile = 'var.h5'
    default, varfile_, default_varfile
    varfile = varfile_
  endelse
;
; Load HDF5 varfile if requested or available.
;
  if (strmid (varfile, strlen(varfile)-3) eq '.h5') then begin
    time = pc_read ('time', file=varfile, datadir=datadir, single=single)
    return
  end
;
; find varfile and set configuration parameters accordingly
;
  pc_find_config, varfile, datadir=datadir, procdir=procdir, procdim=procdim, allprocs=allprocs, reduced=reduced, swap_endian=swap_endian, f77=f77, additional=additional, start_param=param
;
; Set precision for all Pencil Code tools.
;
  pc_set_precision, datadir=datadir, /quiet
;
; Initialize / set default returns for ALL variables.
;
  t=zero
  x=make_array(procdim.mx, type=type_idl)
  y=make_array(procdim.my, type=type_idl)
  z=make_array(procdim.mz, type=type_idl)
  dx=zero
  dy=zero
  dz=zero
  deltay=zero
;
; Build the full path and filename.
;
  filename = procdir + varfile
;
; Check for existence and read the data.
;
  if (not file_test(filename)) then begin
    if (arg_present(exit_status)) then begin
      exit_status=1
      print, 'ERROR: cannot find file '+ filename
      close, /all
      return
    endif else begin
      message, 'ERROR: cannot find file '+ filename
    endelse
  endif
;
; Open a varfile and read some data!
;
  openr, file, filename, f77=f77, swap_endian=swap_endian, /get_lun
  point_lun, file, additional
  if (allprocs eq 1) then begin
    ; collectively written files
    readu, file, t, x, y, z, dx, dy, dz
  endif else if (allprocs eq 2) then begin
    ; xy-collectively written files for each ipz-layer
    readu, file, t
  endif else if (allprocs eq 3) then begin
    ; xy-collectively written files for each ipz-layer in F2003 stream access format
    readu, file, t
  endif else begin
    ; distributed files
    if (param.lshear) then begin
      readu, file, t, x, y, z, dx, dy, dz, deltay
    endif else begin
      readu, file, t, x, y, z, dx, dy, dz
    endelse
  endelse
;
  close, file
  free_lun, file
;
; If requested print a summary (actually the default - unless being quiet).
;
  if (not quiet) then print, ' t = ', t
  time = single ? float(t) : t
;
end
