pro rvid_line_hdf5, field, mpeg=mpeg, tmin=tmin, tmax=tmax, max=amax, min=amin, $
    nrepeat=nrepeat, wait=wait, stride=stride, datadir=datadir, OLDFILE=OLDFILE, $
    test=test, proc=proc, exponential=exponential, map=map, tt=tt, noplot=noplot, $
    extension=extension, sqroot=sqroot, nocontour=nocontour, imgdir=imgdir, $
    squared=squared, exsquared=exsquared, against_time=against_time, func=func, $
    findmax=findmax, csection=csection, xrange=xrange, $
    transp=transp, global_scaling=global_scaling, nsmooth=nsmooth, $
    log=log, xgrid=xgrid, ygrid=ygrid, zgrid=zgrid, psym=psym, help=help, $
    xstyle=xstyle, ystyle=ystyle, fluct=fluct, newwindow=newwindow, xsize=xsize, $
    ysize=ysize, png_truecolor=png_truecolor, noexp=noexp, single=single, $
    xaxisscale=xaxisscale, normalize=normalize, quiet=quiet, _extra=_extra

; $Id$
;+
;  Reads in HDF5 slice files as they are generated by the pencil code.
;  The variable "field" can be changed. Default is 'lnrho'.
;
;  if the keyword /mpeg is given, the file movie.mpg is written.
;  tmin is the time after which data are written
;  nrepeat is the number of repeated images (to slow down movie)
;
;  Typical calling sequence
;  rvid_box_hdf5, 'bz', tmin=190, tmax=200, min=-.35, max=.35, /mpeg
;  rvid_line_hdf5, 'by', proc=0, /xgrid
;  rvid_line_hdf5, 'XX_chiral', proc=0, /xgrid, min=0, max=1
;-

  common pc_precision, zero, one, precision, data_type, data_bytes, type_idl

  if (keyword_set(help)) then begin
    doc_library, 'rvid_line_hdf5'
    return
  endif
;
  default, field, 'lnrho'
  default, datadir, 'data'
  default, imgdir, '.'
  default, nrepeat, 0
  default, stride, 0
  default, tmin, 0.0
  default, tmax, 1e38
  default, wait, 0.03
  default, extension, 'xy'
  default, xgrid, 0
  default, ygrid, 0
  default, zgrid, 0
  default, psym, -2
  default, quiet, 1
  default, single, 0
  default, func, ''

  ; normalization by the rms value at each time step in that case the default should be around 3
  if (keyword_set (normalize)) then default, amax, 2.5
  default, amax, 0.05
  default, amin, -amax

  if (keyword_set (png_truecolor)) then png = 1

  ; do not open a window for PNGs
  if (not keyword_set (png)) then begin
    if (keyword_set (newwindow)) then begin
      window, /free, xsize=xsize, ysize=ysize, title=title
    end
  end

  datadir = pc_get_datadir(datadir)

  pc_read_dim, obj=dim, proc=proc, datadir=datadir, /quiet
  pc_set_precision, dim=dim, /quiet
  nx = dim.nx
  ny = dim.ny
  nz = dim.nz

  pc_read_grid, obj=grid, proc=proc, dim=dim, datadir=datadir, /quiet, single=single
  x = grid.x(dim.l1:dim.l2)
  y = grid.y(dim.m1:dim.m2)
  z = grid.z(dim.n1:dim.n2)

  ; adjust extension for 2D runs
  if ((nx ne 1) and (ny ne 1) and (nz eq 1)) then extension = 'xy'
  if ((nx ne 1) and (ny eq 1) and (nz ne 1)) then extension = 'xz'
  if ((nx eq 1) and (ny ne 1) and (nz ne 1)) then extension = 'yz'

  file_slice = field+'_'+extension+'.h5'

  if (not file_test (datadir+'/slices/'+file_slice)) then begin
    print, 'Slice file "'+datadir+'/slices/'+file_slice+'" does not exist!'
    pos = strpos (file_slice, '_'+extension)
    compfile = strmid (file_slice, 0, pos)+'1_'+extension+'.h5'
    if (file_test (datadir+'/slices/'+compfile)) then print, 'Field name "'+field+'" refers to a vectorial quantity -> select component!'
    return
  end

  if (not keyword_set (quiet)) then print, 'Reading "'+datadir+'/slices/'+file_slice+'"...'
  last = pc_read ('last', filename=file_slice, datadir=datadir+'/slices')

  ; set processor dimensions
  if (is_defined(proc)) then begin
    ipx = proc mod dim.nprocx
    ipy = (proc / dim.nprocx) mod dim.nprocy
    ipz = proc / (dim.nprocx * dim.nprocy)
    indices = [ 0, 1 ]
    if (extension eq 'xz') then indices = [ 0, 2 ]
    if (extension eq 'yz') then indices = [ 1, 2 ]
    start = ([ ipx*nx, ipy*ny, ipz*nz ])[indices]
    count = ([ nx, ny, nz ])[indices]
  end

  if (keyword_set (global_scaling)) then begin
    amax = !Values.F_NaN & amin=amax
    for pos = 1, last, stride+1 do begin
      frame = str (pos)
      plane = pc_read (frame+'/data', start=start, count=count, single=single)
      if (keyword_set (nsmooth)) then plane = smooth (plane, nsmooth)
      amax = max ([ amax, max (plane) ], /NaN)
      amin = min ([ amin, min (plane) ], /NaN)
    end
    if (keyword_set (exponential)) then begin
      amax = exp (amax)
      amin = exp (amin)
    end else if (keyword_set (log)) then begin
      tiny = 1e-30
      amax = alog10 (amax)
      amin = alog10 (amin > tiny)
    end else if (keyword_set (sqroot)) then begin
      amax = sqrt (amax)
      amin = sqrt (amin)
    end
    if (not keyword_set (quiet)) then print, 'Scale using global min, max: ', amin, amax
  end

  if (xgrid) then begin
    xaxisscale = x
  end else if (ygrid) then begin
    xaxisscale = y
  end else if (zgrid) then begin
    xaxisscale = z
  end else begin
    xaxisscale = findgen (max ([ nx, ny, nz ]))
  end

  dev = 'x' ; default: screen output
  if (keyword_set(png)) then begin
    ; switch to Z buffer
    set_plot, 'z'
    ; set window size
    device, SET_RESOLUTION=[ !d.x_size, !d.y_size ]
    ; image counter
    itpng = 0
    dev = 'z'
  end else if (keyword_set (mpeg)) then begin
    ; open MPEG file, if keyword is set
    Nwx = !d.x_size
    Nwy = !d.y_size
    if (!d.name eq 'X') then window, 2, xs=Nwx, ys=Nwy
    mpeg_name = 'movie.mpg'
    print, 'write mpeg movie: ', mpeg_name
    mpegID = mpeg_open ([ Nwx, Nwy ], FILENAME=mpeg_name)
    ; image counter
    itmpeg = 0
  end

  for pos = 1, last, stride+1 do begin
    frame = str (pos)
    index = (pos - 1) / (stride + 1)
    plane = pc_read (frame+'/data', start=start, count=count, single=single)
    t = pc_read (frame+'/time', single=single)

    if (keyword_set (transp)) then plane = transpose (plane)
    plane = reform (plane)
    if (size (plane, /n_dimensions) ge 2) then begin
      default, csection, ((size (plane, /dimensions))[1] + 1) / 2
      plane = reform (plane[*,csection])
    end
    if (keyword_set (sqroot)) then plane = sqrt (plane)
    if (keyword_set (log)) then plane = alog (plane)
    if (keyword_set (squared)) then plane = plane^2
    if (keyword_set (exsquared)) then plane = exp (plane)^2
    if (keyword_set (nsmooth)) then plane = smooth (plane, nsmooth)
    if (keyword_set (fluct)) then plane = plane - mean (plane)
    if (keyword_set (normalize)) then plane = plane / sqrt (mean (plane^2))
    if (func ne '') then begin
      value = plane   ; duplication needed?
      res = execute ('plane='+func, 1)
    end

    if (keyword_set (findmax)) then begin
      ; [PABourdin]: the parameter 'findmax' has no function in the rest of the code, yet!
      ; [PABourdin]: the 'findshock' procedure does not exist in the PC! Therfore commented:
      ;findshock, plane, xaxisscale, leftpnt=leftpnt, rightpnt=rightpnt
      ;max_left = max ([ max_left, leftpnt ], /NaN)
      ;max_right = max ([ [ max_right, rightpnt ], /NaN)
    end

    if (pos eq 1) then tt = t else tt = [ tt, t ]
    if (pos eq 1) then map = plane else map = [ map, plane ]

    if (keyword_set (test)) then begin
      if (not keyword_set (noplot)) then begin
        print, t, min ([ plane, xy, xz, yz ]), max([ plane, xy, xz, yz ])
      end
    end else begin
      if ((t ge tmin) and (t le tmax)) then begin
        if (not keyword_set (noplot)) then begin
          if (keyword_set (exponential)) then begin
            plot, xaxisscale, exp (plane), psym=psym, yrange=[amin,amax], xstyle=xstyle, ystyle=ystyle, xrange=xrange, _extra=_extra
          end else begin
            plot, xaxisscale, plane, psym=psym, yrange=[amin,amax], xstyle=xstyle, ystyle=ystyle, xrange=xrange, _extra=_extra
          end
        end
        if (keyword_set (png)) then begin
          istr2 = string (itpng, '(I4.4)') ; maximum 9999 frames
          image = tvrd ()
          ; make background white, and write png file
          tvlct, red, green, blue, /GET
          imgname = imgdir+'/img_'+istr2+'.png'
          write_png, imgname, image, red, green, blue
          itpng++
        end else if (keyword_set(mpeg)) then begin
          ; write mpeg file directly - for idl_5.5 and later this requires the mpeg license
          image = tvrd (/true)
          for irepeat = 0, nrepeat do begin
            mpeg_put, mpegID, window=2, FRAME=itmpeg, /ORDER
            itmpeg++
          end
          print, index, itmpeg, t, min(plane), max(plane)
        end else begin
          ; default: output on the screen
          if (not keyword_set (noplot)) then print, index, t, min(plane), max(plane)
        end
        wait, wait
        ; check whether file has been written
        if (keyword_set (png)) then spawn, 'ls -l '+imgname
      end
    end
  end

  if (keyword_set(mpeg)) then begin
    ; write & close mpeg file
    print, 'Writing MPEG file..'
    mpeg_save, mpegID, FILENAME=mpeg_name
    mpeg_close, mpegID
  end

;  reform map appropriately

  nxz = n_elements (plane)
  nt = index + 1
  map = reform (map, nxz, nt)

  if (not keyword_set (nocontour)) then begin
    if (keyword_set (against_time)) then begin
      if (keyword_set (noexp)) then begin
        contour, transpose (map), tt, xaxisscale, /fill, nlev=60, ys=1, xs=1
      end else begin
        contour, transpose (exp (map)), tt, xaxisscale, /fill, nlev=60, ys=1, xs=1
      end
    end else begin
      if (keyword_set (noexp)) then begin
        contour, transpose (map), /fill, nlev=60, ys=1, xs=1
      end else begin
        contour, transpose (exp (map)), /fill, nlev=60, ys=1, xs=1
      end
    end
  end

END
