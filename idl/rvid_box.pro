pro rvid_box,field,mpeg=mpeg,png=png,tmin=tmin,tmax=tmax,amax=amax,amin=amin,$
  nrepeat=nrepeat,wait=wait,njump=njump,datadir=datadir,OLDFILE=OLDFILE,$
  test=test,fo=fo,swapz=swapz
;
; $Id: rvid_box.pro,v 1.11 2003-11-21 01:56:09 brandenb Exp $
;
;  Reads in 4 slices as they are generated by the pencil code.
;  The variable "field" can be changed. Default is 'lnrho'.
;
;  if the keyword /mpeg is given, the file movie.mpg is written.
;  tmin is the time after which data are written
;  nrepeat is the number of repeated images (to slow down movie)
;
;  Typical calling sequence
;  rvid_box,'bz',tmin=190,tmax=200,amin=-.35,amax=.35,/mpeg
;  rvid_box,'ss',amax=6.7,fo='(1e9.3)'
;
default,amax,.05
default,amin,-amax
default,field,'lnrho'
default,datadir,'data'
default,nrepeat,0
default,njump,0
default,tmin,0.
default,tmax,1e38
default,wait,.03
default,fo,"(f6.1)"
;
file_slice1=datadir+'/slice_'+field+'.Xy'
file_slice2=datadir+'/slice_'+field+'.xy'
file_slice3=datadir+'/slice_'+field+'.xz'
file_slice4=datadir+'/slice_'+field+'.yz'
;
;  swap z
;
if keyword_set(swapz) then begin
  file_slice2=datadir+'/slice_'+field+'.Xy'
  file_slice1=datadir+'/slice_'+field+'.xy'
endif
;
;  Read the dimensions and precision (single or double) from dim.dat
;
mx=0L & my=0L & mz=0L & nvar=0L & prec=''
nghostx=0L & nghosty=0L & nghostz=0L
;
close,1
openr,1,datadir+'/'+'dim.dat'
readf,1,mx,my,mz,nvar
readf,1,prec
readf,1,nghostx,nghosty,nghostz
close,1
;
nx=mx-2*nghostx
ny=my-2*nghosty
nz=mz-2*nghostz
;

print,nx,ny,nz

t=0. & islice=0
xy2=fltarr(nx,ny)
xy=fltarr(nx,ny)
xz=fltarr(nx,nz)
yz=fltarr(ny,nz)
slice_xpos=0.
slice_ypos=0.
slice_zpos=0.
slice_z2pos=0.
;
;  open MPEG file, if keyword is set
;
dev='x' ;(default)
if keyword_set(png) then begin
  set_plot, 'z'                   ; switch to Z buffer
  device, SET_RESOLUTION=[!d.x_size,!d.y_size] ; set window size
  itpng=0 ;(image counter)
  dev='z'
end else if keyword_set(mpeg) then begin
  ;Nwx=400 & Nwy=320
  Nwx=!d.x_size & Nwy=!d.y_size
  if (!d.name eq 'X') then window,2,xs=Nwx,ys=Nwy
  mpeg_name = 'movie.mpg'
  print,'write mpeg movie: ',mpeg_name
  mpegID = mpeg_open([Nwx,Nwy],FILENAME=mpeg_name)
  itmpeg=0 ;(image counter)
end
;
;  allow for jumping over njump time slices
;  initialize counter
;
ijump=njump ;(make sure the first one is written)
;
close,1 & openr,1,file_slice1,/f77
close,2 & openr,2,file_slice2,/f77
close,3 & openr,3,file_slice3,/f77
close,4 & openr,4,file_slice4,/f77
while not eof(1) do begin
if keyword_set(OLDFILE) then begin ; For files without position
  readu,1,xy2,t
  readu,2,xy,t
  readu,3,xz,t
  readu,4,yz,t
end else begin
  readu,1,xy2,t,slice_z2pos
  readu,2,xy,t,slice_zpos
  readu,3,xz,t,slice_ypos
  readu,4,yz,t,slice_xpos
end
;
if keyword_set(test) then begin
  print,t,min([xy2,xy,xz,yz]),max([xy2,xy,xz,yz])
end else begin
  if t ge tmin and t le tmax then begin
    if ijump eq njump then begin
      ;tvscl,xy2
      boxbotex_scl,xy2,xy,xz,yz,1.,1.,zof=.7,zpos=.34,ip=3,$
          amin=amin,amax=amax,dev=dev
      xyouts,.93,1.13,'!8t!6='+string(t,fo=fo),col=1,siz=2
      if keyword_set(png) then begin
        istr2 = strtrim(string(itpng,'(I20.4)'),2) ;(only up to 9999 frames)
        image = tvrd()
        ;
        ;  make background white, and write png file
        ;
        bad=where(image eq 0) & image(bad)=255
        tvlct, red, green, blue, /GET
        imgname = 'img_'+istr2+'.png'
        write_png, imgname, image, red, green, blue
        itpng=itpng+1 ;(counter)
        ;
      end else if keyword_set(mpeg) then begin
        ;
        ;  write directly mpeg file
        ;  for idl_5.5 and later this requires the mpeg license
        ;
        image = tvrd(true=1)
        for irepeat=0,nrepeat do begin
          mpeg_put, mpegID, window=2, FRAME=itmpeg, /ORDER
          itmpeg=itmpeg+1 ;(counter)
        end
        print,islice,itmpeg,t,min([xy2,xy,xz,yz]),max([xy2,xy,xz,yz])
      end else begin
        ;
        ; default: output on the screen
        ;
        print,islice,t,min([min(xy2),min(xy),min(xz),min(yz)]),$
              max([max(xy2),max(xy),max(xz),max(yz)])
      end
      ijump=0
      wait,wait
      ;
      ; check whether file has been written
      ;
      if keyword_set(png) then spawn,'ls -l '+imgname
      ;
    end else begin
      ijump=ijump+1
    end
  end
  islice=islice+1
end
end
close,1
close,2
close,3
close,4
;
;  write & close mpeg file
;
if keyword_set(mpeg) then begin
  print,'Writing MPEG file..'
  mpeg_save, mpegID, FILENAME=mpeg_name
  mpeg_close, mpegID
end
;
END
