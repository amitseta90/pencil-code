;
;  $Id: rvid_box.pro 9840 2008-09-05 07:29:37Z ajohan $
;
;  Reads in 4 slices as they are generated by the pencil code.
;  The variable "field" can be changed. Default is 'lnrho'.
;
;  If the keyword /mpeg is given, the file movie.mpg is written.
;  tmin is the time after which data are written
;  nrepeat is the number of repeated images (to slow down movie)
;  An alternative is to set the /png_truecolor flag and postprocess the
;  PNG images with ${PENCIL_HOME}/utils/makemovie (requires imagemagick
;  and mencoder to be installed).
;
;  Typical calling sequence
;    rvid_box, 'bz', tmin=190, tmax=200, min=-.35, max=.35, /mpeg
;    rvid_box, 'ss', max=6.7, fo='(1e9.3)'
;
;  For 'gyroscope' look:
;    rvid_box, 'oz', tmin=-1, tmax=1001, /shell, /centred, r_int=0.5, r_ext=1.0
;
;  For centred slices, but without masking outside shell
;    rvid_box, 'oz', tmin=-1, tmax=1010, /shell, /centred, r_int=0.0, r_ext=5.0
;
;  For slice position m
;    rvid_box, field, tmin=0, min=-amax, max=amax, /centred, /shell, $
;       r_int=0., r_ext=8., /z_topbot_swap
;
;  For masking of shell, but leaving projections on edges of box
;    rvid_box, 'oz', tmin=-1, tmax=1001, /shell, r_int=0.5, r_ext=1.0
;
;  If using /centred, the optional keywords /z_bot_twice and /z_top_twice
;  plot the bottom or top xy-planes (i.e. xy and xy2, respectively) twice.
;  (Once in the centred position, once at the bottom of the plot; cf. the
;  default, which plots the top slice in the centred position.)
;  (This can be useful for clarifying hidden features in gyroscope plots.)
;
pro rvid_box_sph, field, $
  mpeg=mpeg, png=png, truepng=png_truecolor, tmin=tmin, tmax=tmax, $
  max=amax,min=amin, noborder=noborder, imgdir=imgdir, $
  nrepeat=nrepeat, wait=wait, njump=njump, datadir=datatopdir, $
  noplot=noplot, fo=fo, swapz=swapz, xsize=xsize, ysize=ysize, $
  title=title, itpng=itpng, global_scaling=global_scaling, proc=proc, $
  exponential=exponential, sqroot=sqroot, logarithmic=logarithmic, $
  shell=shell, centred=centred, colmpeg=colmpeg,$
  z_bot_twice=z_bot_twice, z_top_twice=z_top_twice, $
  z_topbot_swap=z_topbot_swap, xrot=xrot, zrot=zrot, zof=zof, $
  magnify=magnify, xpos=xpos, zpos=zpos, xmax=xmax, ymax=ymax, $
  xlabel=xlabel, ylabel=ylabel, label=label, size_label=size_label, $
  monotonous_scaling=monotonous_scaling, symmetric_scaling=symmetric_scaling, $
  nobottom=nobottom, oversaturate=oversaturate, cylinder=cylinder, $
  tunit=tunit, qswap=qswap, bar=bar, nolabel=nolabel, norm=norm, $
  divbar=divbar, blabel=blabel, bsize=bsize, bformat=bformat, thlabel=thlabel, $
  bnorm=bnorm, swap_endian=swap_endian, newwindow=newwindow, $
  quiet_skip=quiet_skip,zoomz=zoomz,nointerpz=nointerpz,$
  orig_aspect=orig_aspect,axes=axes
;
common pc_precision, zero, one
;
default,amax,0.05
default,amin,-amax
default,field,'lnrho'
default,dimfile,'dim.dat'
default,varfile,'var.dat'
default,nrepeat,0
default,njump,0
default,tmin,0.0
default,tmax,1e38
default,wait,0.0
default,fo,"(f6.1)"
default,xsize,512
default,ysize,448
default,title,''
default,itpng,0 ;(image counter)
default,noborder,[0,0,0,0,0,0]
;default,r_int,0.5
;default,r_ext,1.0
default,imgdir,'.'
default,magnify,1.0
default,xpos,0.0
default,zpos,0.34
default,xrot,30.0
default,zrot,30.0
default,zof,0.7
default,xmax,1.0
default,ymax,1.0
default,xlabel,0.08
default,ylabel,1.18
default,label,''
default,size_label,1.4
default,thlabel,1.0
default,nobottom,0.0
default,monotonous_scaling,0.0
default,oversaturate,1.0
default,tunit,1.0
default,norm,1.0
default,swap_endian,0
default,quiet_skip,1
default,zoomz,1.0
default,nointerpz,0
;
if (keyword_set(newwindow)) then window, xsize=xsize, ysize=ysize
if (keyword_set(png_truecolor)) then png=1
;
first_print = 1
;
; Construct location of slice_var.plane files 
;
if (not keyword_set(datatopdir)) then datatopdir=pc_get_datadir()
;  by default, look in data/, assuming we have run read_videofiles.x before:
datadir=datatopdir
if (n_elements(proc) le 0) then begin
  pc_read_dim, obj=dim, datadir=datatopdir
  if (dim.nprocx*dim.nprocy*dim.nprocz eq 1) then datadir=datatopdir+'/proc0'
endif else begin
  datadir=datatopdir+'/'+proc
endelse
;
; Read slices
;
file_slice1=datadir+'/slice_'+field+'.xz'
file_slice2=datadir+'/slice_'+field+'.xy'
file_slice3=datadir+'/slice_'+field+'.xy2'
file_slice4=datadir+'/slice_'+field+'.xy3'
file_slice5=datadir+'/slice_'+field+'.xy4'
;
;  Read the dimensions from dim.dat
;
pc_read_dim, obj=dim, datadir=datadir, /quiet
pc_read_param,obj=param & r_int=param.r_int & r_ext=param.r_ext
;
;  Set single or double precision.
;
pc_set_precision, dim=dim, /quiet
;
mx=dim.mx & my=dim.my & mz=dim.mz
nx=dim.nx & ny=dim.ny & nz=dim.nz
nghostx=dim.nghostx & nghosty=dim.nghosty & nghostz=dim.nghostz
ncpus = dim.nprocx*dim.nprocy*dim.nprocz
;
;if (keyword_set(shell)) then begin
;
;  Need full grid to mask outside shell.
;
  pc_read_grid, obj=grid, /quiet
  rad=grid.x & tht=grid.y & phi=grid.z
;
  rr = spread(rad, [1,2], [my,mz])
  tt = spread(tht, [0,2], [mx,mz])
  pp = spread(phi, [0,1], [mx,my])
;
; assume slices are all central for now -- perhaps generalize later
; nb: need pass these into boxbotex_scl for use after scaling of image;
;     otherwise pixelisation can be severe...
; nb: at present using the same z-value for both horizontal slices.
  irad=mx/2 & itht=my/2 
  iphi1=nghostz    
  iphi2=nghostz+   mz/4
  iphi3=nghostz+ 2*mz/4
  iphi4=nghostz+ 3*mz/4  
;
t=zero
rp =fltarr(nx,nz)*one
rt1=fltarr(nx,ny)*one
rt2=fltarr(nx,ny)*one
rt3=fltarr(nx,ny)*one
rt4=fltarr(nx,ny)*one

slice_ypos=zero
slice_z1pos=zero
slice_z2pos=zero
slice_z3pos=zero
slice_z4pos=zero
;
;  Open MPEG file, if keyword is set.
;
dev='x' ;(default)
if (keyword_set(png)) then begin
  set_plot, 'z'                        ; switch to Z buffer
  device, set_resolution=[xsize,ysize] ; set window size
  dev='z'
endif else if (keyword_set(mpeg)) then begin
  if (!d.name eq 'X') then wdwset, 2, xs=xsize, ys=ysize
  mpeg_name = 'movie.mpg'
  print, 'write mpeg movie: ', mpeg_name
  mpegID = mpeg_open([xsize,ysize], filename=mpeg_name)
  itmpeg=0 ;(image counter)
endif else begin
  if (!d.name eq 'X') then wdwset,xs=xsize,ys=ysize
endelse
;
;  Redefine min and max according to mathematical operation.
;
if (keyword_set(sqroot)) then begin
  amin=sqrt(amin) & amax=sqrt(amax)
endif
;
if (keyword_set(exponential)) then begin
  amin=exp(amin) & amax=exp(amax)
endif
;
if (keyword_set(logarithmic)) then begin
  amin=alog(amin) & amax=alog(amax)
endif
;
;  Go through all video snapshots and find global min and max.
;
if (keyword_set(global_scaling)) then begin
;
  first=1L
;
  close, 1 & openr, 1, file_slice1, /f77, swap_endian=swap_endian
  close, 2 & openr, 2, file_slice2, /f77, swap_endian=swap_endian
  close, 3 & openr, 3, file_slice3, /f77, swap_endian=swap_endian
  close, 4 & openr, 4, file_slice4, /f77, swap_endian=swap_endian
  close, 5 & openr, 5, file_slice5, /f77, swap_endian=swap_endian
;
  while (not eof(1)) do begin
;
    readu, 1, rp , t, slice_ypos
    readu, 2, rt1, t, slice_z1pos
    readu, 3, rt2, t, slice_z2pos
    readu, 4, rt3, t, slice_z3pos 
    readu, 5, rt4, t, slice_z4pos
;
    if (first) then begin
      amax=max([max(rt2),max(rt1),max(rp),max(rt3),max(rt4)])
      amin=min([min(rt2),min(rt1),min(rp),min(rt3),min(rt4)])
      first=0L
    endif else begin
      amax=max([amax,max(rt2),max(rt1),max(rp),max(rt3),max(rt4)])
      amin=min([amin,min(rt2),min(rt1),min(rp),min(rt3),min(rt4)])
    endelse
;
  endwhile
;
  close, 1 & close, 2 & close, 3 & close, 4 & close, 5
;
  print,'Scale using global min, max: ', amin, amax
;
endif
;
;  Open slice files for reading.
;
close, 1 & openr, 1, file_slice1, /f77, swap_endian=swap_endian
close, 2 & openr, 2, file_slice2, /f77, swap_endian=swap_endian
close, 3 & openr, 3, file_slice3, /f77, swap_endian=swap_endian
close, 4 & openr, 4, file_slice4, /f77, swap_endian=swap_endian
close, 5 & openr, 5, file_slice5, /f77, swap_endian=swap_endian
;
islice=0L
;

while ( (not eof(1)) and (t le tmax) ) do begin
;
  if ( (t ge tmin) and (t le tmax) and (islice mod (njump+1) eq 0) ) then begin
    readu, 1, rp , t, slice_ypos
    readu, 2, rt1, t, slice_z1pos
    readu, 3, rt2, t, slice_z2pos
    readu, 4, rt3, t, slice_z3pos 
    readu, 5, rt4, t, slice_z4pos
 
  endif else begin ; Read only time.
    dummy=zero
    readu, 1, rp, t
    readu, 2, dummy & readu, 3, dummy & readu, 4, dummy & readu, 5, dummy 
  endelse
;
;  Possible to set time interval and to jump over njump slices.
;
  if ( (t ge tmin) and (t le tmax) and (islice mod (njump+1) eq 0) ) then begin
;
;  Perform preset mathematical operation on data before plotting.
;
    if (keyword_set(sqroot)) then begin      
      rp=sqrt(rp) & rt1=sqrt(rt1) & rt2=sqrt(rt2) & rt3=sqrt(rt3) & rt4=sqrt(rt4)
    endif
;
    if (keyword_set(exponential)) then begin      
      rp=exp(rp) & rt1=exp(rt1) & rt2=exp(rt2) & rt3=exp(rt3) & rt4=exp(rt4)
    endif
;
    if (keyword_set(logarithmic)) then begin      
      rp=alog(rp) & rt1=alog(rt1) & rt2=alog(rt2) & rt3=alog(rt3) & rt4=alog(rt4)
    endif
;
;  If monotonous scaling is set, increase the range if necessary.
;
    if (keyword_set(monotonous_scaling)) then begin
      amax1=max([amax,max(rp),max(rt1),max(rt2),max(rt3),max(rt4)])
      amin1=min([amin,min(rp),min(rt1),min(rt2),min(rt3),min(rt4)])
      amax=(4.*amax+amax1)/5.
      amin=(4.*amin+amin1)/5.
    endif
;
;  Symmetric scaling about zero.
;
    if (keyword_set(symmetric_scaling)) then begin
      amax=amax>abs(amin)
      amin=-amax
    endif
;
;  If noborder is set.
;
    s=size(rp)  & l1=noborder(0) & l2=s[1]-1-noborder(1)
                  n1=noborder(4) & n2=s[2]-1-noborder(5)
    s=size(rt1) & m1=noborder(2) & m2=s[2]-1-noborder(3)
;
;  Cut the arrays - leftover from swapz of rvid_box
;
    rps = rp(l1:l2,n1:n2)
    rt1s=rt1(l1:l2,m1:m2)
    rt2s=rt2(l1:l2,m1:m2)
    rt3s=rt3(l1:l2,m1:m2)
    rt4s=rt4(l1:l2,m1:m2)
;
;  Convert midplane to cartesian coordinates
;
    fcrp=pc_cyl2cart(rps,rad[dim.l1:dim.l2],phi[dim.n1:dim.n2])
    rps=fcrp.field
;
;  For masking, rr at constant theta 
;
    xx=rebin(fcrp.xc,n_elements(fcrp.xc),n_elements(fcrp.yc))
    yy=rebin(transpose(fcrp.yc),n_elements(fcrp.xc),n_elements(fcrp.yc))
    trr=sqrt(xx^2+yy^2)
    xc=fcrp.xc
    yc=fcrp.yc
;
;  Convert meridional plane to cartesian if the keyword is set
;
    if (keyword_set(nointerpz)) then begin
      ;will use the meridional slices as they are.
      ;rr at constant phi, for masking  
      prr=rr(nghostx:mx-nghostx-1,nghosty:my-nghosty-1,iphi1)
      ;tt at constant phi, for masking
      ptt=tt(nghostx:mx-nghostx-1,nghosty:my-nghosty-1,iphi1)
      zm=tht
      xm=rad
    endif else begin
      ;will interpolate the meridional plane to cartesian
      fcrt1=pc_meridional(rt1s,rad[dim.l1:dim.l2],tht[dim.m1:dim.m2])
      fcrt2=pc_meridional(rt2s,rad[dim.l1:dim.l2],tht[dim.m1:dim.m2])
      fcrt3=pc_meridional(rt3s,rad[dim.l1:dim.l2],tht[dim.m1:dim.m2])
      fcrt4=pc_meridional(rt4s,rad[dim.l1:dim.l2],tht[dim.m1:dim.m2])
;
      ;the quantity fields
      rt1s=fcrt1.field & rt2s=fcrt2.field 
      rt3s=fcrt3.field & rt4s=fcrt4.field
;
      ;rr at constant phi, for masking
      xx=rebin(fcrt1.xc,n_elements(fcrt1.xc),n_elements(fcrt1.zc))
      zz=rebin(transpose(fcrt1.zc),n_elements(fcrt1.xc),n_elements(fcrt1.zc))
      prr=sqrt(xx^2+zz^2)
      ;tt at constant phi, for masking
      ptt=atan(xx,zz) 
;
      xm=fcrt1.xc
      zm=fcrt1.zc
    endelse
;
    boxbotex_scl_sph,rps,rt1s,rt2s,rt3s,rt4s,$
      1.,1.,rad=rad,tht=tht,phi=phi,xc=xc,yc=yc,xm=xm,zm=zm,$
      ip=3,zof=.36,zpos=.25,$
      amin=amin,amax=amax,dev=dev,$
      scale=1.4,$
      r_int=r_int,r_ext=r_ext,trr=trr,prr=prr,ptt=ptt,$
      nobottom=nobottom,norm=norm,xrot=xrot,zrot=zrot,zoomz=zoomz,$
      nointerpz=nointerpz,orig_aspect=orig_aspect
;
    xyouts, .08, 0.81, '!8t!6='+string(t/tunit,fo=fo)+'!c'+title, $
      col=1,siz=1.6
              
;
;  Draw color bar.
;
    if (keyword_set(bar)) then begin
        default, bsize, 1.5
        default, bformat, '(f5.2)'
        default, bnorm, 1.
        default, divbar, 2
        default, blabel, ''
        !p.title=blabel
        colorbar, pos=[.82,.15,.84,.85], color=1, div=divbar,$
            range=[amin,amax]/bnorm, /right, /vertical, $
            format=bformat, charsize=bsize, title=title
        !p.title=''
    endif
;
;  Draw axes
;
      if (keyword_set(axes)) then begin
        xx=!d.x_size & yy=!d.y_size
        aspect_ratio=1.*yy/xx
        ; length of the arrow
        length=0.1 
        xlength=length & ylength=xlength/aspect_ratio 
        ; rotation angles. I didn't figure out exactly 
        ; the rotation law. This .7 is an ugly hack 
        ; that looks good for most angles
        gamma=.7*xrot*!pi/180.
        alpha=zrot*!pi/180.
        ; position of the origin
        x0=0.12 & y0=0.25
        ;
        ; x arrow
        ;
        x1=x0+xlength*(cos(gamma)*cos(alpha)) 
        y1=y0+ylength*(sin(gamma)*sin(alpha))
        angle=atan((y1-y0),(x1-x0))
        x2=x0+length*cos(angle)
        y2=y0+length*sin(angle)
        ;arrow, x0, y0, x1, y1,color=100,/normal
        arrow, x0, y0, x2, y2,col=1,/normal,$
          thick=thlabel,hthick=thlabel
        xyouts,x2-0.01,y2-0.045,'!8x!x',col=1,/normal,$
        siz=size_label,charthick=thlabel
        ;
        ; y arrow
        ;
        x1=x0+xlength*(-cos(gamma)*sin(alpha))
        y1=y0+ylength*( sin(gamma)*cos(alpha))
        angle=atan((y1-y0),(x1-x0))
        x2=x0+length*cos(angle)
        y2=y0+length*sin(angle)
        ;arrow, x0, y0, x1, y1,color=100,/normal
        arrow, x0, y0, x2, y2,col=1,/normal,$
          thick=thlabel,hthick=thlabel
        xyouts,x2-0.03,y2-0.01,'!8y!x',col=1,/normal,$
        siz=size_label,charthick=thlabel
        ;
        ; z arrow
        ;
        x1=x0 & y1=y0+ylength
        arrow, x0, y0, x1, y1,col=1,/normal,$
          thick=thlabel,hthick=thlabel
        xyouts,x1-0.015,y1+0.01,'!8z!x',col=1,/normal,$
          siz=size_label,charthick=thlabel
      endif


;
;  Save as png file.
;
    if (keyword_set(png)) then begin
        istr2 = strtrim(string(itpng,'(I20.4)'),2) ;(only up to 9999 frames)
        image = tvrd()
;
;  Make background white, and write png file.
;
        bad=where(image eq 0) & image(bad)=255
        tvlct, red, green, blue, /GET
        imgname = 'img_'+istr2+'.png'
        write_png, imgdir+'/'+imgname, image, red, green, blue
        if (keyword_set(png_truecolor)) then $
            spawn, 'mogrify -type TrueColor ' + imgdir+'/'+imgname
        itpng=itpng+1         ;(counter)
;
    endif else if (keyword_set(mpeg)) then begin
;
;  Write mpeg file directly.
;  NOTE: For idl_5.5 and later this requires the mpeg license.
;
        image = tvrd(true=1)
;
        if (keyword_set(colmpeg)) then begin
;ngrs seem to need to work explictly with 24-bit color to get
;     color mpegs to come out on my local machines...
          image24 = bytarr(3,xsize,ysize)
          tvlct, red, green, blue, /GET
        endif
;
        for irepeat=0,nrepeat do begin
          if (keyword_set(colmpeg)) then begin
            image24[0,*,*]=red(image[0,*,*])
            image24[1,*,*]=green(image[0,*,*])
            image24[2,*,*]=blue(image[0,*,*])
            mpeg_put, mpegID, image=image24, frame=itmpeg, /order
          endif else begin
            mpeg_put, mpegID, window=2, frame=itmpeg, /order
          endelse
          itmpeg=itmpeg+1     ;(counter)
        endfor
;
        if (first_print) then $
            print, '   islice    itmpeg       min/norm     max/norm     amin         amax'
        first_print = 0
        print, islice, itmpeg, t, $
            min([min(xy2),min(xy),min(xz),min(yz)])/norm, $
            max([max(xy2),max(xy),max(xz),max(yz)])/norm, $
            amin, amax
;
    endif else begin
;
;  Default: output on the screen
;
        if (first_print) then $
            print, '   islice        t        min/norm     max/norm        amin         amax'
        first_print = 0

        print, islice, t, $
            min([min(rp),min(rt1),min(rt2),min(rt3),min(rt4)])/norm, $
            max([max(rp),max(rt1),max(rt2),max(rt3),max(rt4)])/norm, $
            amin, amax, format='(i9,5f13.7)'
    endelse
;
;  Wait in case movie runs to fast.
;      
      wait, wait
;
;  Check whether file has been written.
;
      if (keyword_set(png)) then spawn, 'ls -l '+imgdir+'/'+imgname
;
  endif else begin
;
;  Skip this slice if not in time interval or if jumping.
;
    if (not quiet_skip) then $
        print, 'Skipping slice number '+strtrim(islice,2)+ $
               ' at time t=', t
  endelse
;
;  Ready for next video slice.
;
  islice=islice+1
;
endwhile
;
;  Inform the user of why program stopped.
;
if (t gt tmax) then begin
  print, 'Stopping since t>', strtrim(tmax,2)
endif else begin
  print, 'Read last slice at t=', strtrim(t,2)
endelse
;
;  Close slice files.
;
close, 1 & close, 2 & close, 3 &close, 4
;
;  Write and close mpeg file.
;
if (keyword_set(mpeg)) then begin
  print,'Writing MPEG file...'
  mpeg_save, mpegID, filename=mpeg_name
  mpeg_close, mpegID
endif
;
end
