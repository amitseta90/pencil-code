! $Id: run.f90,v 1.115 2002-11-23 21:02:59 brandenb Exp $
!
!***********************************************************************
      program run
!
!  solve the isothermal hydro equation in 3-D
!
!-----------------------------------------------------------------------
!   1-apr-01/axel+wolf: coded
!  17-aug-01/axel: ghost layers implemented
!  11-sep-01/axel: adapted from burgers_phi
!
        use Cdata
        use General
        use Mpicomm
        use Sub
        use IO
        use Register
        use Global
        use Param_IO
        use Equ
        use Gravity
        use Slices
        use Print
        use Timestep
        use Wsnaps
        use Boundcond
        use Power_spectrum
        use Timeavg
!
        implicit none
!
        real, dimension (mx,my,mz,mvar) :: f,df
        double precision :: time1,time2
        integer :: count
        logical :: stop=.false.,reload=.false.,save_lastsnap=.true.
        real :: wall_clock_time
!
!  initialize MPI and register physics modules
!  (must be done before lroot can be used, for example)
!
        call initialize
!
!  call signal handler (for compaq machine only)
!  currently disabled; want to put as include file
!
!!     call siginit
!!     call signonbrutal
!
!  identify version
!
        if (lroot) call cvs_id( &
             "$Id: run.f90,v 1.115 2002-11-23 21:02:59 brandenb Exp $")
!
!  read parameters from start.x (default values; may be overwritten by
!  read_runpars)
!
        call rparam()
!
!  derived parameters (that may still be overwritten)
!  [might better be put into another routine, possibly even in rparam or
!  read_runpars]
!
!  [Currently none]
!
!  read parameters and output parameter list
!
        call read_runpars(FILE=.true.,ANNOTATION='Running')
        call rprint_list(.false.)
!
!  print resolution
!
        if (lroot) print*, 'nxgrid,nygrid,nzgrid=',nxgrid,nygrid,nzgrid
!
!  set up directory names `directory' and `directory_snap'
!
      call directory_names()
!
!  read data
!  snapshot data are saved in the tmp subdirectory.
!  This directory must exist, but may be linked to another disk.
!  NOTE: for io_dist, rtime doesn't read the time, only for io_mpio.
!
        if (ip<=6.and.lroot) print*,'reading var files'
        call input(trim(directory_snap)//'/var.dat',f,mvar,1)
        call rtime(trim(directory)//'/time.dat',t)
        call rglobal()      ! Read global variables (if there are)
!
!  read coordinates
!
        if (ip<=6.and.lroot) print*,'reading grid coordinates'
        call rgrid(trim(directory)//'/grid.dat')
!
!  get state length of random number generator
!
        call get_nseed(nseed)
!
!  run initialization of individual modules
!
        call ss_run_hook()      ! calculate radiative conductivity, etc.
        call forcing_run_hook() ! get random seed from file, ..
        call timeavg_run_hook(f) ! initialize time averages
!
!  Write data to file for IDL
!
      call wparam2()
!
!  possible debug output (can only be done after "directory" is set)
!  check whether mn array is correct
!
      if(ip<=3) call debug_imn_arrays
!
!  setup gravity (obtain coefficients cpot(1:5); initialize global array gg)
!
        if (lgravr) call setup_grav()
!
        call wglobal()
!
!  advance equations
!  NOTE: headt=.true. in order to print header titles
!
        if(lroot) then
          time1 = mpiwtime()
          count = 0
        endif
!
!  update ghost zones, so rprint works corrected for at the first
!  time step even if we didn't read ghost zones
!
        call update_ghosts(f)
!
!  save spectrum snapshot
!
        if (dspec/=impossible) call powersnap(f)
!
!  do loop in time
!
        Time_loop: do it=1,nt
          lout=mod(it-1,it1).eq.0
          if (lout) then
            !
            ! exit DO loop if file `STOP' exists
            !
            if (lroot) inquire(FILE="STOP", EXIST=stop)
            call mpibcast_logical(stop, 1)
            if (stop.or.t>tmax) then
              if (lroot) then
                if (stop) write(0,*) "done: found STOP file"
                if (t>tmax) write(0,*) "done: t > tmax"
                call remove_file("STOP")
              endif
              exit Time_loop
            endif
            !
            !  re-read parameters if file `RELOAD' exists; then remove
            !  the file
            !
            if (lroot) inquire(FILE="RELOAD", EXIST=reload)
            call mpibcast_logical(reload, 1)
            if (reload) then
              if (lroot) write(0,*) "Found RELOAD file -- reloading parameters"
              ! Re-read configuration
              call read_runpars(PRINT=.true.,FILE=.true.,ANNOTATION='Reloading')
              call rprint_list(.true.) !(Re-read output list)
              if (lroot) call remove_file("RELOAD")
              reload = .false.
            endif
          endif
          !
          !  Remove wiggles in lnrho in sporadic time intervals.
          !  Necessary on moderate-sized grids. When this happens,
          !  this is often an indication of bad boundary conditions!
          !  iwig=500 is a typical value. For iwig=0 no action is taken.
          !  (The two queries below must come separately on compaq machines.)
          !
          if (iwig/=0) then
            if (mod(it,iwig).eq.0) then
              if (lrmwig_xyaverage) call rmwig_xyaverage(f,ilnrho)
              if (lrmwig_full) call rmwig(f,df,ilnrho,awig)
              if (lrmwig_rho) call rmwig(f,df,ilnrho,awig,explog=.true.)
            endif
          endif
          !
          !  If we want to write out video data, wvid sets lvid=.true.
          !  This allows pde to prepare some of the data
          !
          call wvid_prepare()
          !
          !  time advance
          !
          call rk_2n(f,df)
          count = count + 1     !  reliable loop count even for premature exit
          !
          !  update time averages
          !
          if (ltavg) call update_timeavgs(f,dt)
          !
          !  advance shear parameter and add forcing (if applicable)
          !
          if (lshear) call advance_shear()
          if (lforcing) call addforce(f)
          !
          !  in regular intervals, calculate certain averages
          !  and do other output.
          !
          if(lout) call write_xyaverages()
          if(lout.and.lwrite_zaverages) call write_zaverages()
          if(lout) call prints()
          !
          !  Setting ialive=1 can be useful on flaky machines!
          !  Earch processor writes it's processor number (if it is alive!)
          !  Set ialive=0 to fully switch this off
          !
          if (ialive /= 0) then
            if (mod(it,ialive)==0) &
                 call outpui(trim(directory)//'/alive.info', &
                 spread(it,1,1) ,1) !(all procs alive?)
          endif
          call wsnap(trim(directory_snap)//'/VAR',f,.true.)
          call wsnap_timeavgs(trim(directory_snap)//'/TAVG',.true.)
          !
          !  Write slices (for animation purposes)
          !
          if(lvid) call wvid(f,trim(directory)//'/slice_')
          !
          !  save snapshot every isnap steps in case the run gets interrupted
          !  the time needs also to be written
          !
          if (isave /= 0) then
            if (mod(it,isave)==0) then
              call wsnap(trim(directory_snap)//'/var.dat',f,.false.)
              call wsnap_timeavgs(trim(directory_snap)//'/timeavg.dat',.false.)
              call wtime(trim(directory)//'/time.dat',t)
            endif
          endif
          !
          !  save spectrum snapshot
          !
          if (dspec /= impossible) call powersnap(f)
          !
          !  do exit when timestep has become too short.
          !  This may indicate an MPI communication problem,
          !  so the data are useless and won't be saved!
          !
          if ((it < nt) .and. (dt < dtmin)) then
            write(0,*) 'Time step has become too short: dt = ', dt
            save_lastsnap=.false.
            exit Time_loop
          endif
          !
          headt=.false.
        enddo Time_loop
        if(lroot) time2=mpiwtime()
!
!  write data at end of run for restart
!  dvar is written for analysis purposes only
!
        if(save_lastsnap) then
          call wsnap(trim(directory_snap)//'/var.dat',f,.false.)
          call wtime(trim(directory)//'/time.dat',t)
          if (ip<=10) call wsnap(trim(directory)//'/dvar.dat',df,.false.)
        endif
!
!  save spectrum snapshot
!
        if(save_lastsnap) then
          if(dspec /= impossible) then
            if(vel_spec) call power(f,'u')
            if(mag_spec) call power(f,'b')
            if(vec_spec) call power(f,'a')
            if(ab_spec)  call powerhel(f,'mag')
            if(ou_spec)  call powerhel(f,'kin')
          endif
        endif
!
!  write seed parameters (only if forcing is turned on)
!
        if (lforcing) then
          call random_seed_wrapper(get=seed(1:nseed))
          call outpui(trim(directory)//'/seed.dat',seed,nseed)
        endif
!
!  print wall clock time and time per step and processor
!  for diagnostic purposes
!
        if(lroot) then
          wall_clock_time = time2-time1
          print*
          print*, 'Wall clock time [sec]=', Wall_clock_time, &
               ' (+/- ', real(mpiwtick()),')'
          if (it>1) print*, 'Wall clock time/timestep/meshpoint [microsec]=', &
               wall_clock_time/count/nw/ncpus/1e-6
          print*
        endif
        call mpifinalize
!
      endprogram run
