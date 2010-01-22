! $Id$
!
!  Module for NSCBC (Navier-Stokes Characteristic Boundary Conditions).  
!  NSCBC is an alternative way of imposing (time-dependent) boundary 
!  conditions through solving differential equations on the boundaries.
!
! 2009.09.09 (Nils Erland) : Moved all NSCBC stuff from boundcond.f90 to 
!                            this module.
!
module NSCBC
!
  use Cdata
  use Cparam
  use Messages
  use Mpicomm
!
  implicit none
!
include 'NSCBC.h'
!
! Format: nscbc_bc = 'bottom_x:top_x','bottom_y:top_y','bottom_z:top_z'
! for top and bottom boundary treatment at x, y and z-boundaries.
!
! nscbc_bc1(1) refers to boundary treatment at bottom x-boundary, nscbc_bc2(1)
! at top x-boundary etc.
! fbcx1, fbcx2 etc. are still used to impose values of variables at the
! boundaries.
!
! nscbc_sigma is a parameter describing how fast the velocity will reach
! an imposed velocity at an inlet in the absence of outgoing waves. How
! to set it is case dependent.
!
  character(len=2*nscbc_len+1), dimension(3) :: nscbc_bc=''
  character(len=nscbc_len), dimension(3) :: nscbc_bc1,nscbc_bc2
  character (len=labellen), dimension(ninit) :: inlet_profile='nothing'
  character(len=40) :: turb_inlet_dir=''
  real :: nscbc_sigma_out = 1.,nscbc_sigma_in = 1., p_infty=1.
  logical :: inlet_from_file=.false., jet_inlet=.false.
  logical :: first_NSCBC=.true.,onesided_inlet=.true.
!
!  Variables to be used when getting timevarying inlet from file
!
  real, allocatable, dimension(:,:,:,:) :: f_in
  real, allocatable, dimension(:) :: x_in
  real, allocatable, dimension(:) :: y_in
  real, allocatable, dimension(:) :: z_in
  character :: prec_in
  real :: t_in,dx_in,dy_in,dz_in
  integer :: mx_in,my_in,mz_in,nv_in
  integer :: l1_in, nx_in, ny_in, nz_in
  integer :: mvar_in,maux_in,mglobal_in
  integer :: nghost_in,ipx_in, ipy_in, ipz_in
  integer :: m1_in  
  integer :: n1_in
  integer :: l2_in
  integer :: m2_in
  integer :: n2_in
  real :: Lx_in
  real :: Ly_in
  real :: Lz_in
  real :: smooth_time=0.
!
  namelist /NSCBC_init_pars/  &
      nscbc_bc, nscbc_sigma_in, nscbc_sigma_out, p_infty, inlet_from_file,&
      turb_inlet_dir, jet_inlet
!
  namelist /NSCBC_run_pars/  &
      nscbc_bc, nscbc_sigma_in, nscbc_sigma_out, p_infty, inlet_from_file,&
      turb_inlet_dir,jet_inlet,inlet_profile,smooth_time,onesided_inlet
!
  contains
!***********************************************************************
    subroutine nscbc_boundtreat(f,df)
!
!  Boundary treatment of the df-array. 
!
!  This is a way to impose (time-
!  dependent) boundary conditions by solving a so-called characteristic
!  form of the fluid equations on the boundaries, as opposed to setting 
!  actual values of the variables in the f-array. The method is called 
!  Navier-Stokes characteristic boundary conditions (NSCBC).
!  The current implementation only solves a simplified version of the
!  equations, namely a set of so-called local one-dimensional inviscid
!  (LODI) relations. This means that transversal and viscous terms are
!  dropped on the boundaries.
!
!  The treatment should be done after the y-z-loop, but before the Runge-
!  Kutta solver adds to the f-array.
!
!   7-jul-08/arne: coded.
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df

      intent(inout) :: f
      intent(inout) :: df
!
      if (nscbc_bc1(1) /= '' .or. nscbc_bc2(1) /= '') &
          call nscbc_boundtreat_xyz(f,df,1)
      if (nscbc_bc1(2) /= '' .or. nscbc_bc2(2) /= '') &
          call nscbc_boundtreat_xyz(f,df,2)
      if (nscbc_bc1(3) /= '' .or. nscbc_bc2(3) /= '') &
          call nscbc_boundtreat_xyz(f,df,3)
     
    endsubroutine nscbc_boundtreat
!***********************************************************************
    subroutine nscbc_boundtreat_xyz(f,df,j)
!
!   NSCBC boundary treatment.
!   j = 1, 2 or 3 for x, y or z-boundaries respectively.
!
!   7-jul-08/arne: coded.

!
      use General, only: safe_character_assign, chn
      use Chemistry, only: bc_nscbc_subin_x,bc_nscbc_nref_subout_x,&
          bc_nscbc_nref_subout_y,bc_nscbc_nref_subout_z

      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df
      character (len=nscbc_len), dimension(3) :: bc12
      character (len=3) :: topbot
      character (len=60) :: turbfile
      integer j,k,ip_ok,ip_test
      real, dimension(mcom) :: valx,valy,valz
      logical :: proc_at_inlet
      integer :: ipx_in, ipy_in, ipz_in, iproc_in, nprocx_in, nprocy_in, nprocz_in
      character (len=120) :: directory_in
      character (len=5) :: chproc_in
      real :: T_t,u_t

      intent(inout) :: f
      intent(inout) :: df
      intent(in)    :: j
!
      proc_at_inlet=.false.
!
      do k=1,2                ! loop over 'bot','top'
        if (k==1) then
          topbot='bot'; bc12(j)=nscbc_bc1(j);!val=bt_val1(j)
          valx=fbcx1; valy=fbcy1; valz=fbcz1; ip_ok=0
        else
          topbot='top'; bc12(j)=nscbc_bc2(j);!val=bt_val2(j)
          valx=fbcx2; valy=fbcy2; valz=fbcz2
          if (j==1) ip_ok=nprocx-1
          if (j==2) ip_ok=nprocy-1
          if (j==3) ip_ok=nprocz-1
        endif
        if (j==1) ip_test=ipx
        if (j==2) ip_test=ipy
        if (j==3) ip_test=ipz
!
! Read data to be used at the inlet from file
!
        if (inlet_from_file) then
!
! Read data from file only initially
! At later times this is stored in processor memory.
! NILS: Is it really a good idea to store all this in memory?
!
          if (first_NSCBC) then
!
! Check which processor we want to read from.
! In the current implementation it is required that:
!   1) The number of mesh points and processors at the interface between 
!      the two computational domains are equal. The two comp. domains I 
!      am refering to here is the domain of the current simulation and the
!      domain of the pre-run isotropic turbulence simulation defining the
!      turbulence at the inlet.
!   2) The pre-run simulaion can not have multiple processors in the flow
!      direction of the current simulation.   
!          
            if (lprocz_slowest) then
              ipx_in=ipx
              ipy_in=ipy
              ipz_in=ipz
              nprocx_in=nprocx
              nprocy_in=nprocy
              nprocz_in=nprocz
              if (j==1) then
                if ((topbot=='bot'.and.ipx==0).or.&
                    (topbot=='top'.and.ipx==nprocx-1)) then
                  proc_at_inlet=.true.
                  ipx_in=0
                  nprocx_in=1
                endif
              elseif (j==2) then
                if ((topbot=='bot'.and.ipy==0).or.&
                    (topbot=='top'.and.ipy==nprocy-1)) then
                  proc_at_inlet=.true.
                  ipy_in=0
                  nprocy_in=1
                endif
              elseif (j==3) then
                if ((topbot=='bot'.and.ipz==0).or.&
                    (topbot=='top'.and.ipz==nprocz-1)) then
                  proc_at_inlet=.true.
                  ipz_in=0
                  nprocz_in=1
                endif
              else
                call fatal_error("nscbc_boundtreat_xyz",'No such direction!')
              endif
              iproc_in=ipz_in*nprocy_in*nprocx_in+ipy_in*nprocx_in+ipx_in
            else
              call fatal_error("nscbc_boundtreat_xyz",&
                  'lprocz_slowest=F not implemeted for inlet from file!')
            endif
!
!  Read data only if required, i.e. if we are at a processor handling inlets
!
            if (proc_at_inlet) then
              call chn(iproc_in,chproc_in)
              call safe_character_assign(directory_in,&
                  trim(turb_inlet_dir)//'/data/proc'//chproc_in)
              call safe_character_assign(turbfile,&
                  trim(directory_in)//'/var.dat')
              open(1,FILE=turbfile,FORM='unformatted')
              if (ip<=8) print*,'input: open, mx_in,my_in,mz_in,nv_in=',&
                  mx_in,my_in,mz_in,nv_in
              read(1) f_in
              read(1) t_in,x_in,y_in,z_in,dx_in,dy_in,dz_in
              nx_in=mx_in-2*nghost
              ny_in=my_in-2*nghost
              nz_in=mz_in-2*nghost
              l1_in=nghost+1
              m1_in=nghost+1
              n1_in=nghost+1
              l2_in=mx_in-nghost
              m2_in=my_in-nghost
              n2_in=mz_in-nghost
              Lx_in=x_in(l2_in+1)-x_in(l1_in)
              Ly_in=y_in(m2_in+1)-y_in(m1_in)
              Lz_in=z_in(n2_in+1)-z_in(n1_in)
              first_NSCBC=.false.
              close(1)
            endif            
          endif
        endif
!
!  Check if this is a physical boundary
!
        if (ip_test==ip_ok) then
!
!  Set the values of T_t and u_t dependent on direction
!
          T_t=0
          if (j==1) then 
            if (ilnTT > 0) T_t=valx(ilnTT)
            u_t=valx(j)
          elseif (j==2) then 
            if (ilnTT > 0) T_t=valy(ilnTT)
            u_t=valy(j)
          elseif (j==3) then 
            if (ilnTT > 0) T_t=valz(ilnTT)
            u_t=valz(j)
          endif
!
!  Do the NSCBC boundary
!
          select case (bc12(j))
!
          case ('part_ref_outlet')
            call bc_nscbc_prf(f,df,j,topbot,.false.)
! 
          case ('part_ref_inlet')
            call bc_nscbc_prf(f,df,j,topbot,.true.,linlet=.true.,u_t=u_t,T_t=T_t)
!
          case ('ref_inlet')
            call bc_nscbc_prf(f,df,j,topbot,.false.,linlet=.true.,u_t=u_t,T_t=T_t)
!
          case ('subsonic_inflow')
            if (j==1) then
              call bc_nscbc_subin_x(f,df,topbot,valx)
            elseif (j==2) then
            endif
!
          case ('subson_nref_outflow')
            if (j==1) then
              call bc_nscbc_nref_subout_x(f,df,topbot,nscbc_sigma_out)
            elseif (j==2) then
              call bc_nscbc_nref_subout_y(f,df,topbot,nscbc_sigma_out)
            elseif (j==3) then
              call bc_nscbc_nref_subout_z(f,df,topbot,nscbc_sigma_out)
            endif
          case ('')
!   Do nothing.
          case ('none')
            print*,'nscbc_boundtreat_xyz: doing nothing!'
!   Do nothing.
          case default
            call fatal_error("nscbc_boundtreat_xyz",&
                'You must specify nscbc bouncond!')
          endselect
        endif
      enddo
!
    endsubroutine
!***********************************************************************
    subroutine bc_nscbc_prf(f,df,dir,topbot,non_reflecting_inlet,linlet,u_t,T_t)
!
!   Calculate du and dlnrho at a partially reflecting outlet/inlet normal to 
!   x-direction acc. to LODI relations. Uses a one-sided finite diff. stencil.
!
!   7-jul-08/arne: coded.
!  25-nov-08/nils: extended to work in multiple dimensions and with cross terms
!                  i.e. not just the LODI equations.
!  22-jan-10/nils: made general with respect to direction such that we do not
!                  need three different routines for the three different 
!                  directions.
!
      use Deriv, only: der_onesided_4_slice, der_pencil, der2_pencil
      use Chemistry
      use General, only: random_number_wrapper

      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df
      character (len=3) :: topbot
      logical, optional :: linlet
      logical :: llinlet, non_reflecting_inlet
      real, optional :: u_t, T_t
      real :: Mach,KK,nu, cs0_average
      integer, dimension(30) :: stat
      integer lll,i,jjj,kkk,j,k,ngridpoints
      integer sgn,dir,iused,dir1,dir2,dir3,igrid,jgrid
      logical :: non_zero_transveral_velo
      real, allocatable, dimension(:,:,:,:) :: dui_dxj
      real, allocatable, dimension(:,:,:) :: &
          fslice, dfslice,grad_rho,u_in,grad_T,grad_P
      real, allocatable, dimension(:,:) :: &
          TT,mu1,grad_mu1,rho0,P0,L_1,L_2,L_3,L_4,L_5,&
          prefac1,prefac2,T_1,T_2,T_3,T_4,T_5,cs,&
          cs2,gamma,dYk_dx
!
      intent(inout) :: f
      intent(inout) :: df
!
!  Define the direction of this boundary
!
      llinlet = .false.
      if (present(linlet)) llinlet = linlet
      if (llinlet.and..not.present(u_t)) call stop_it(&
           'bc_nscbc_prf: when using linlet=T, you must also specify u_t)')
      if (llinlet.and.ilnTT>0.and..not.present(T_t)) call stop_it(&
           'bc_nscbc_prf: when using linlet=T, you must also specify T_t)')
      select case (topbot)
      case ('bot')
        if (dir == 1) lll = l1
        if (dir == 2) lll = m1
        if (dir == 3) lll = n1
        sgn = 1
      case ('top')
        if (dir == 1) lll = l2
        if (dir == 2) lll = m2
        if (dir == 3) lll = n2
        sgn = -1
      case default
        print*, "bc_nscbc_prf: ", topbot, " should be `top' or `bot'"
      endselect
!
!  Set some auxillary variables
!
      if (dir==1) then
        dir1=1; dir2=2; dir3=3
        igrid=ny; jgrid=nz
      elseif (dir==2) then
        dir1=2; dir2=1; dir3=3
        igrid=nx; jgrid=nz
      elseif (dir==3) then
        dir1=3; dir2=1; dir3=2
        igrid=nx; jgrid=ny
      else
        call fatal_error('bc_nscbc_prf:','No such dir!')
      endif
!
!  Allocate all required arrays
!
      stat=0
      allocate(  fslice(igrid,jgrid,mfarray),STAT=stat(1))
      allocate( dfslice(igrid,jgrid,mvar   ),STAT=stat(2))
      allocate(      TT(igrid,jgrid),        STAT=stat(3))
      allocate(     mu1(igrid,jgrid),        STAT=stat(4))
      allocate(grad_mu1(igrid,jgrid),        STAT=stat(5)) 
      allocate(    rho0(igrid,jgrid),        STAT=stat(6))
      allocate(      P0(igrid,jgrid),        STAT=stat(7))     
      allocate(     L_1(igrid,jgrid),        STAT=stat(8))
      allocate(     L_2(igrid,jgrid),        STAT=stat(9))
      allocate(     L_3(igrid,jgrid),        STAT=stat(10))
      allocate(     L_4(igrid,jgrid),        STAT=stat(11))
      allocate(     L_5(igrid,jgrid),        STAT=stat(12))
      allocate( prefac1(igrid,jgrid),        STAT=stat(13))
      allocate( prefac2(igrid,jgrid),        STAT=stat(14))            
      allocate(     T_1(igrid,jgrid),        STAT=stat(15))
      allocate(     T_2(igrid,jgrid),        STAT=stat(16))
      allocate(     T_3(igrid,jgrid),        STAT=stat(17))
      allocate(     T_4(igrid,jgrid),        STAT=stat(18))
      allocate(     T_5(igrid,jgrid),        STAT=stat(19))
      allocate(      cs(igrid,jgrid),        STAT=stat(20))
      allocate(     cs2(igrid,jgrid),        STAT=stat(21))
      allocate(   gamma(igrid,jgrid),        STAT=stat(22))
      allocate(  dYk_dx(igrid,jgrid),        STAT=stat(23))
      allocate(grad_rho(igrid,jgrid,3),      STAT=stat(24))
      allocate(    u_in(igrid,jgrid,3),      STAT=stat(25))
      allocate(  grad_T(igrid,jgrid,3),      STAT=stat(26))
      allocate(  grad_P(igrid,jgrid,3),      STAT=stat(27))
      allocate( dui_dxj(igrid,jgrid,3,3),    STAT=stat(28))
      if (maxval(stat) > 0) &
          call stop_it("Couldn't allocate memory for all vars in bc_nscbc_prf")
!
!  Initialize fslice and dfslice
!
      if (dir == 1) then
        fslice=f(lll,m1:m2,n1:n2,:)
        dfslice=df(lll,m1:m2,n1:n2,:)
      elseif (dir == 2) then
        fslice=f(l1:l2,lll,n1:n2,:)
        dfslice=df(l1:l2,lll,n1:n2,:)
      elseif (dir == 3) then
        fslice=f(l1:l2,m1:m2,lll,:)     
        dfslice=df(l1:l2,m1:m2,lll,:)     
      else
        call fatal_error('bc_nscbc_prf','No such dir!')
      endif
!
!  Find derivatives at boundary
!
      call derivate_boundary(f,sgn,dir1,lll,dui_dxj,grad_T,grad_rho)
!
!  Get some thermodynamical variables
!  This includes values and gradients of; density, temperature, pressure
!  In addition also speed of sound, gamma and mu1 is found.
!
      call get_thermodynamics(mu1,grad_mu1,gamma,cs2,cs,rho0,TT,P0,nu,&
          grad_rho,grad_P,grad_T,lll,sgn,dir1,fslice)
!
!  Define some prefactors to be used later
!
      prefac1 = -1./(2.*cs2)
      prefac2 = -1./(2.*rho0*cs)
!
!  Find Mach number 
!  (NILS: I do not think this is a good way to determine the Mach
!  number since this is a local Mach number for this processor. Furthermore
!  by determining the Mach number like this we will see the Mach number varying
!  with the phase of an acoustic wave as the wave pass through the boundary.
!  I think that what we really want is a Mach number averaged over the 
!  timescale of several acoustic waves. How could this be done????)
!
      ngridpoints=igrid*jgrid
      Mach=sum(fslice(:,:,dir1)/cs)/ngridpoints
!
!  We will need the transversal terms of the waves entering the domain
!
      call transversal_terms(T_1,T_2,T_3,T_4,T_5,rho0,P0,gamma,&
          fslice,grad_rho,grad_P,dui_dxj,dir1,dir2,dir3)
!
      if (llinlet) then
!
!  Find the velocity to be used at the inlet.
!
        if (dir==1) then
          call find_velocity_at_inlet(u_in,non_zero_transveral_velo,&
              Lx_in,nx_in,u_t,dir,m1_in,m2_in,n1_in,n2_in)
        elseif(dir==2) then
          call find_velocity_at_inlet(u_in,non_zero_transveral_velo,&
              Ly_in,ny_in,u_t,dir,l1_in,l2_in,n1_in,n2_in)
        elseif(dir==3) then
          call find_velocity_at_inlet(u_in,non_zero_transveral_velo,&
              Lz_in,nz_in,u_t,dir,l1_in,l2_in,m1_in,m2_in)
        endif
!
!  Having found the velocity at the inlet we are now ready to start
!  defining the L's, which are really the Lodi equations.
!
        L_1 = (fslice(:,:,dir1) - sgn*cs)&
            *(grad_P(:,:,dir1) - sgn*rho0*cs*dui_dxj(:,:,dir1,dir1))
        if (non_reflecting_inlet) then
          if (ilnTT>0) then
            call fatal_error('NSCBC.f90',&
                'non reflecting inlet is not implemented for ilnTT>0')
          else
            L_2=0
          endif
!
!  The inlet is non-reflecting only when nscbc_sigma_in is set to 0, this 
!  might however lead to problems as the inlet velocity will tend to drift 
!  away from the target velocity u_t. This problem should be overcome by 
!  setting a small but non-zero nscbc_sigma_in.
!
          L_3=nscbc_sigma_in*(fslice(:,:,dir2)-u_in(:,:,dir2))&
              *cs/Lxyz(dir1)-T_3
          L_4=nscbc_sigma_in*(fslice(:,:,dir3)-u_in(:,:,dir3))&
              *cs/Lxyz(dir1)-T_4
          L_5 = nscbc_sigma_in*cs2*rho0&
              *sgn*(fslice(:,:,dir1)-u_in(:,:,dir1))*(1-Mach**2)/Lxyz(dir1)&
              -(T_5+sgn*rho0*cs*T_2)
        else
          L_3=0
          L_4=0
          L_5 = L_1
          L_2=0.5*(gamma-1)*(L_5+L_1)
        endif
      else
!
!  Find the parameter determining 
!
        cs0_average=sum(cs)/ngridpoints
        KK=nscbc_sigma_out*(1-Mach**2)*cs0_average/Lxyz(dir1)
!
!  Find the L_i's. 
!
        L_1 = KK*(P0-p_infty)-(T_5-sgn*rho0*cs*T_2)
        if (ilnTT > 0) then 
          L_2=fslice(:,:,dir1)*(cs2*grad_rho(:,:,dir1)-grad_P(:,:,dir1))
        else
          L_2=0
        endif
        L_3 = fslice(:,:,dir1)*dui_dxj(:,:,dir2,dir1)
        L_4 = fslice(:,:,dir1)*dui_dxj(:,:,dir3,dir1)
        L_5 = (fslice(:,:,dir1) - sgn*cs)*&
             (grad_P(:,:,dir1)&
             - sgn*rho0*cs*dui_dxj(:,:,dir1,dir1))
      endif
!
!  Find the evolution equation for the normal velocity at the boundary
!  For 'top' L_1 plays the role of L5 and L_5 the role of L1
!
      select case (topbot)
      case ('bot')
        if (llinlet) then
          dfslice(:,:,dir1) = prefac2*( L_5 - L_1)-T_2
        else
          dfslice(:,:,dir1) = prefac2*( L_1 - L_5)!-parallell_term_ux
        endif
      case ('top')
        if (llinlet) then
          dfslice(:,:,dir1) = prefac2*( L_1 - L_5)!-parallell_term_ux
        else
          dfslice(:,:,dir1) = prefac2*(-L_1 + L_5)-T_2
        endif
      endselect
!
!  Find the evolution equation for the other equations at the boundary
!
      dfslice(:,:,ilnrho) = prefac1*(2*L_2 + L_1 + L_5)-T_1
      if (ilnTT>0) then
        dfslice(:,:,ilnTT) = -1./(rho0*cs2)*(-L_2+0.5*(gamma-1.)*(L_5+L_1))*TT
      endif
      dfslice(:,:,dir2) = -L_3-T_3
      dfslice(:,:,dir3) = -L_4-T_4
!
!  Check if we are solving for logrho or rho
!
      if (.not. ldensity_nolog) then
        dfslice(:,:,ilnrho)=dfslice(:,:,ilnrho)/rho0
      endif
!
!  Check if we are solving for logT or T
!
      if (.not. ltemperature_nolog .and. ilnTT>0) then
        dfslice(:,:,ilnTT)=dfslice(:,:,ilnTT)/TT
      endif
!
! Impose required variables at the boundary
!
      if (llinlet) then
        if (.not. non_reflecting_inlet) then
          fslice(:,:,dir1) = u_in(:,:,dir1)
          if (non_zero_transveral_velo) then
            fslice(:,:,dir2) = u_in(:,:,dir2)
            fslice(:,:,dir3) = u_in(:,:,dir3)
          else
            fslice(:,:,dir2) = 0.
            fslice(:,:,dir3) = 0.
          endif
          if (ilnTT>0) then
            fslice(:,:,ilnTT) = T_t
          endif
        endif
      endif 
!
! Treat all other variables as passive scalars
!
      iused=max(ilnTT,ilnrho)
      if (mvar>iused) then 
        do k=iused+1,mvar
          call der_onesided_4_slice(f,sgn,k,dYk_dx,lll,dir1)
          dfslice(:,:,k)=-fslice(:,:,dir1)*dYk_dx
        enddo
      endif
!
!  Put everything that has been temporarily stored in dfslice back into
!  the df array
!
      if (dir == 1) then
        df(lll,m1:m2,n1:n2,:)=dfslice
        f( lll,m1:m2,n1:n2,:)=fslice
      elseif (dir == 2) then
        df(l1:l2,lll,n1:n2,:)=dfslice
        f( l1:l2,lll,n1:n2,:)=fslice
      elseif (dir == 3) then
        df(l1:l2,m1:m2,lll,:)=dfslice
        f( l1:l2,m1:m2,lll,:)=fslice
      else
        call fatal_error('bc_nscbc_prf','No such dir!')
      endif 
!
    endsubroutine bc_nscbc_prf
!***********************************************************************
    subroutine bc_nscbc_prf_y(f,df,topbot,non_reflecting_inlet,linlet,u_t,T_t)
!
!   Calculate du and dlnrho at a partially reflecting outlet/inlet normal to 
!   y-direction acc. to LODI relations. Uses a one-sided finite diff. stencil.
!
!   7-jul-08/arne: coded.
!  25-nov-08/nils: extended to work in multiple dimensions and with cross terms
!                  i.e. not just the LODI equations.
!
      use EquationOfState, only: cs0, cs20
      use Deriv, only: der_onesided_4_slice, der_pencil, der2_pencil
      use Chemistry
      use Viscosity

      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df
      character (len=3) :: topbot
      logical, optional :: linlet
      logical :: llinlet, non_reflecting_inlet
      real, optional :: u_t,T_t
      real, dimension(nx,nz) :: dlnrho_dx,dlnrho_dy,dlnrho_dz
      real, dimension(nx,nz) :: rho0, L_1, L_3, L_4, L_5,parallell_term_uz
      real, dimension(nx,nz) :: parallell_term_rho
      real, dimension(nx,nz) :: parallell_term_ux
      real, dimension(nx,nz) :: prefac1, prefac2,parallell_term_uy
      real, dimension(nx,nz,3) :: grad_rho, u_in
      real, dimension(nx,nz,3,3) :: dui_dxj
      real, dimension (mx,mz) :: cs0_ar,cs20_ar
      real, dimension (mx,mz) :: tmp22,tmp12,tmp2_lnrho,tmp33,tmp13,tmp3_lnrho
      real, dimension (mx,mz) :: tmp23,tmp32,tmp21,tmp31,tmp11,tmp1_lnrho
      real, dimension (nx) :: tmpx
      real, dimension (nz) :: tmpz
      real :: Mach,KK,nu
      integer lll,i
      integer sgn
      real :: shift, grid_shift, weight, round
      integer :: iround,lowergrid,uppergrid

      intent(inout) :: f
      intent(inout) :: df


      llinlet = .false.
      if (present(linlet)) llinlet = linlet
      if (llinlet.and..not.present(u_t)) call stop_it(&
           'bc_nscbc_prf_y: when using linlet=T, you must also specify u_t)')
      select case (topbot)
      case ('bot')
        lll = m1
        sgn = 1
      case ('top')
        lll = m2
        sgn = -1
      case default
        print*, "bc_nscbc_prf_y: ", topbot, " should be `top' or `bot'"
      endselect
!
!  Find density
!
      if (ldensity_nolog) then
        rho0 = f(l1:l2,lll,n1:n2,irho)
      else
        rho0 = exp(f(l1:l2,lll,n1:n2,ilnrho))
      endif
!
!  Get viscoity
!
      call getnu(nu)
!
!  Set arrays for the speed of sound and for the speed of sound squared (is it
!  really necessarry to have both arrays?) 
!  Set prefactors to be used later.
!
      if (leos_idealgas) then
        cs20_ar(l1:l2,n1:n2)=cs20
        cs0_ar(l1:l2,n1:n2)=cs0
        prefac1 = -1./(2.*cs20)
        prefac2 = -1./(2.*rho0*cs0)
      elseif (leos_chemistry) then
        call fatal_error('bc_nscbc_prf_x',&
            'This sub routine is not yet adapted to work with leos_chemsitry!')
      else
        print*,"bc_nscbc_prf_y: leos_idealgas=",leos_idealgas,"."
        print*,"NSCBC boundary treatment only implemented for an ideal gas." 
        print*,"Boundary treatment skipped."
        return
      endif
!
!  Calculate one-sided derivatives in the boundary normal direction
!
      call der_onesided_4_slice(f,sgn,ilnrho,grad_rho(:,:,2),lll,2)
      call der_onesided_4_slice(f,sgn,iux,dui_dxj(:,:,1,2),lll,2)
      call der_onesided_4_slice(f,sgn,iuy,dui_dxj(:,:,2,2),lll,2)
      call der_onesided_4_slice(f,sgn,iuz,dui_dxj(:,:,3,2),lll,2)
!
!  Do central differencing in the directions parallell to the boundary 
!  first in the x-direction......
!
      if (nxgrid /= 1) then
        do i=n1,n2
          call der_pencil(1,f(:,lll,i,iuy),tmp21(:,i))
          call der_pencil(1,f(:,lll,i,ilnrho),tmp1_lnrho(:,i))
          call der_pencil(1,f(:,lll,i,iux),tmp11(:,i))
          call der_pencil(1,f(:,lll,i,iuz),tmp31(:,i))
        enddo
      else
        tmp31=0
        tmp21=0
        tmp11=0
        tmp1_lnrho=0
      endif
      dui_dxj(:,:,3,1)=tmp31(l1:l2,n1:n2)
      dui_dxj(:,:,2,1)=tmp21(l1:l2,n1:n2)
      dui_dxj(:,:,1,1)=tmp11(l1:l2,n1:n2)
      grad_rho(:,:,1)=tmp1_lnrho(l1:l2,n1:n2)
!
!  .... then in the z-direction
!
      if (nzgrid /= 1) then
        do i=l1,l2
          call der_pencil(3,f(i,lll,:,iuz),tmp33(i,:))
          call der_pencil(3,f(i,lll,:,ilnrho),tmp3_lnrho(i,:))
          call der_pencil(3,f(i,lll,:,iux),tmp13(i,:))
          call der_pencil(3,f(i,lll,:,iuy),tmp23(i,:))
        enddo
      else
        tmp33=0
        tmp23=0
        tmp13=0
        tmp3_lnrho=0
      endif
      dui_dxj(:,:,3,3)=tmp33(l1:l2,n1:n2)
      dui_dxj(:,:,2,3)=tmp23(l1:l2,n1:n2)
      dui_dxj(:,:,1,3)=tmp13(l1:l2,n1:n2)
      grad_rho(:,:,3)=tmp3_lnrho(l1:l2,n1:n2)
!
!  Find divergence of rho if we solve for logarithm of rho
!
      if (.not. ldensity_nolog) then
        do i=1,3
          grad_rho(:,:,i)=grad_rho(:,:,i)*rho0
        enddo
      endif
!
!  Find Mach number 
!  (NILS: I do not think this is a good way to determine the Mach
!  number since this is a local Mach number for this processor. Furthermore
!  by determining the Mach number like this we will see the Mach number varying
!  with the phase of an acoustic wave as the wave pass through the boundary.
!  I think that what we really want is a Mach number averaged over the 
!  timescale of several acoustic waves. How could this be done????)
!
      Mach=sum(f(l1:l2,lll,n1:n2,iuy)/cs0_ar(l1:l2,n1:n2))/(nx*nz)
!
!  Find the L_i's (which really are the Lodi equations)
!
      if (llinlet) then
        L_1 = (f(l1:l2,lll,n1:n2,iuy) - sgn*cs0_ar(l1:l2,n1:n2))*&
            (cs20_ar(l1:l2,n1:n2)*grad_rho(:,:,2) &
            - sgn*rho0*cs0_ar(l1:l2,n1:n2)*dui_dxj(:,:,2,2))
!
!  Find velocity at inlet
!
        if (inlet_from_file) then
          if (Ly_in == 0) call fatal_error('bc_nscbc_prf_y',&
              'Ly_in=0. Check that the precisions are the same.')
          round=t*u_t/Ly_in
          iround=int(round)
          shift=round-iround
          grid_shift=shift*ny_in
          lowergrid=m1_in+int(grid_shift)
          uppergrid=lowergrid+1
          weight=grid_shift-int(grid_shift)
          u_in(:,:,:)&
              =f_in(l1_in:l2_in,lowergrid,n1_in:n2_in,iux:iuz)*(1-weight)&
              +f_in(l1_in:l2_in,uppergrid,n1_in:n2_in,iux:iuz)*weight
          u_in(:,:,2)=u_in(:,:,2)+u_t
        else
          u_in(:,:,1)=0.
          u_in(:,:,2)=u_t
          u_in(:,:,3)=0.
        endif
        if (non_reflecting_inlet) then
!
!  The inlet is non-reflecting only when nscbc_sigma_in is set to 0, this 
!  might however lead to problems as the inlet velocity will tend to drift 
!  away from the target velocity u_t. This problem should be overcome by 
!  setting a small but non-zero nscbc_sigma_in.
!
          L_3=nscbc_sigma_in*(f(l1:l2,lll,n1:n2,iux)-u_in(:,:,1))&
              *cs0_ar(l1:l2,n1:n2)/Lxyz(2)
          L_4=nscbc_sigma_in*(f(l1:l2,lll,n1:n2,iuz)-u_in(:,:,3))&
              *cs0_ar(l1:l2,n1:n2)/Lxyz(2)
          L_5 = nscbc_sigma_in*cs20_ar(l1:l2,n1:n2)*rho0&
              *sgn*(f(l1:l2,lll,n1:n2,iuy)-u_in(:,:,2))*(1-Mach**2)/Lxyz(2)
        else
          L_3=0
          L_4=0
          L_5 = L_1
        endif
      else
!
!  Find the parameter determining 
!
        KK=nscbc_sigma_out*(1-Mach**2)*cs0/Lxyz(2)
!
!  Find the L_i's
!
        L_1 = KK*(rho0*cs20-p_infty)
        L_3 = f(l1:l2,lll,n1:n2,iuy)*dui_dxj(:,:,1,2)
        L_4 = f(l1:l2,lll,n1:n2,iuy)*dui_dxj(:,:,3,2)
        L_5 = (f(l1:l2,lll,n1:n2,iuy) - sgn*cs0_ar(l1:l2,n1:n2))*&
             (cs20_ar(l1:l2,n1:n2)*grad_rho(:,:,2)&
             -sgn*rho0*cs0_ar(l1:l2,n1:n2)*dui_dxj(:,:,2,2))
      endif
!
!  Add terms due to derivatives parallell to the boundary
!
!!$      parallell_term_rho &
!!$          =rho0*dui_dxj(:,:,1,1)+f(l1:l2,lll,n1:n2,iux)*grad_rho(:,:,1)&
!!$          +rho0*dui_dxj(:,:,3,3)+f(l1:l2,lll,n1:n2,iuz)*grad_rho(:,:,3)
!!$      parallell_term_ux &
!!$           =f(l1:l2,lll,n1:n2,iux)*dui_dxj(:,:,1,1)&
!!$           +f(l1:l2,lll,n1:n2,iuz)*dui_dxj(:,:,1,3)&
!!$           +cs20_ar(l1:l2,n1:n2)*grad_rho(:,:,1)/rho0&
!!$           +nu*(d2u1_dx2+d2u1_dz2)
!!$      parallell_term_uy &
!!$           =f(l1:l2,lll,n1:n2,iux)*dui_dxj(:,:,2,1)&
!!$           +f(l1:l2,lll,n1:n2,iuz)*dui_dxj(:,:,2,3)&
!!$           +nu*(d2u2_dx2+d2u2_dz2)
!!$      parallell_term_uz &
!!$           =f(l1:l2,lll,n1:n2,iux)*dui_dxj(:,:,3,1)&
!!$           +f(l1:l2,lll,n1:n2,iuz)*dui_dxj(:,:,3,3)&
!!$           +cs20_ar(l1:l2,n1:n2)*grad_rho(:,:,3)/rho0&
!!$           +nu*(d2u3_dx2+d2u3_dz2)

!print*,'y----------------------------------------------------'
!!$print*,'ux=',f(l1:l2,lll,n1:n2,iux)
!!$print*,'uz=',f(l1:l2,lll,n1:n2,iuz)
!!$print*,'dui_dxj(:,:,2,1)=',dui_dxj(:,:,2,1)
!!$print*,'dui_dxj(:,:,2,3)=',dui_dxj(:,:,2,3)
!!$print*,'parallell_term_uy=',parallell_term_uy
!!$print*,maxval(f(l1:l2,lll,n1:n2,iux)),maxval(dui_dxj(:,:,2,1))
!!$print*,maxval(f(l1:l2,lll,n1:n2,iuz)),maxval(dui_dxj(:,:,2,3))
!!$print*,minval(f(l1:l2,lll,n1:n2,iux)),minval(dui_dxj(:,:,2,1))
!!$print*,minval(f(l1:l2,lll,n1:n2,iuz)),minval(dui_dxj(:,:,2,3))
!!$print*,minval(parallell_term_rho),maxval(parallell_term_rho)
!!$print*,minval(parallell_term_ux),maxval(parallell_term_ux)
!!$print*,minval(parallell_term_uy),maxval(parallell_term_uy)
!!$print*,minval(parallell_term_uz),maxval(parallell_term_uz)

!!$
!!$
!!$
      parallell_term_rho=0
      parallell_term_ux=0
      parallell_term_uy=0
      parallell_term_uz=0
!
!  Find the evolution equations at the boundary
!
      select case (topbot)
      ! NB: For 'top' L_1 plays the role of L5 and L_5 the role of L1
      case ('bot')
        df(l1:l2,lll,n1:n2,ilnrho) = prefac1*(L_5 + L_1)-parallell_term_rho
        if (llinlet) then
          df(l1:l2,lll,n1:n2,iuy) = prefac2*( L_5 - L_1)-parallell_term_uy
        else
          df(l1:l2,lll,n1:n2,iuy) = prefac2*(-L_5 + L_1)-parallell_term_uy
        endif
        df(l1:l2,lll,n1:n2,iux) = -L_3-parallell_term_ux
        df(l1:l2,lll,n1:n2,iuz) = -L_4-parallell_term_uz
      case ('top')
        df(l1:l2,lll,n1:n2,ilnrho) = prefac1*(L_1 + L_5)-parallell_term_rho
        if (llinlet) then
          df(l1:l2,lll,n1:n2,iuy) = prefac2*(-L_5 + L_1)-parallell_term_uy
        else
          df(l1:l2,lll,n1:n2,iuy) = prefac2*( L_5 - L_1)-parallell_term_uy
        endif
        df(l1:l2,lll,n1:n2,iux) = -L_3-parallell_term_ux
        df(l1:l2,lll,n1:n2,iuz) = -L_4-parallell_term_uz
      endselect
!
!  Check if we are solving for logrho or rho
!
      if (.not. ldensity_nolog) then
        df(l1:l2,lll,n1:n2,irho)=df(l1:l2,lll,n1:n2,irho)/rho0
      endif
!
! Impose required variables at the boundary
!
      if (llinlet) then
        if (.not. non_reflecting_inlet) then
          f(l1:l2,lll,n1:n2,iux) = u_in(:,:,1)
          f(l1:l2,lll,n1:n2,iuy) = u_in(:,:,2)
          f(l1:l2,lll,n1:n2,iuz) = u_in(:,:,3)
        endif
      endif
!
    endsubroutine bc_nscbc_prf_y
!***********************************************************************
    subroutine read_NSCBC_init_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat
      integer :: i 

      if (present(iostat)) then
        read(unit,NML=NSCBC_init_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=NSCBC_init_pars,ERR=99)
      endif
!
      do i=1,3
        if (nscbc_bc(i) /= '') lnscbc = .true.
      enddo
!
      if (lnscbc) call parse_nscbc(nscbc_bc,nscbc_bc1,nscbc_bc2)
!
99    return
!
    endsubroutine read_NSCBC_init_pars
!***********************************************************************
    subroutine read_NSCBC_run_pars(unit,iostat)

      use Sub, only : rdim

      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat
      integer :: i,stat 
      logical :: exist
      character (len=130) :: file
!
! Define default for the inlet_profile for backward compatibility
!
      inlet_profile(1)='uniform'
!
      if (present(iostat)) then
        read(unit,NML=NSCBC_run_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=NSCBC_run_pars,ERR=99)
      endif
!
      do i=1,3
        if (nscbc_bc(i) /= '') lnscbc = .true.
      enddo
!
      if (lnscbc) call parse_nscbc(nscbc_bc,nscbc_bc1,nscbc_bc2)
!
! Check if we will read turbulent inlet data from data file
!
      if (inlet_from_file) then
        print*,'Read inlet data from file!'
!
! Read the size of the data to be found on the file.
!
!print*,'turb_inlet_dir=',turb_inlet_dir
        file=trim(turb_inlet_dir)//'/data/proc0/dim.dat'
        inquire(FILE=trim(file),EXIST=exist)
        if (exist) then
          call rdim(file,&
              mx_in,my_in,mz_in,mvar_in,maux_in,mglobal_in,prec_in,&
              nghost_in,ipx_in, ipy_in, ipz_in)
          nv_in=mvar_in+maux_in+mglobal_in
        else
          print*,'file=',file
          call stop_it('read_NSCBC_run_pars: Could not find file!')
        endif
!
! Allocate array for data to be used at the inlet.
! For now every processor reads all the data - this is clearly an overkill,
! but we leav it like this during the development of this feature.
!
        allocate( f_in(mx_in,my_in,mz_in,nv_in),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for f_in ")
        allocate( x_in(mx_in),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for x_in ")
        allocate( y_in(my_in),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for y_in ")
        allocate( z_in(mz_in),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for z_in ")
      endif
!
99    return
!
    endsubroutine read_NSCBC_run_pars
!***********************************************************************
    subroutine write_NSCBC_init_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit,NML=NSCBC_init_pars)
!
    endsubroutine write_NSCBC_init_pars
!***********************************************************************
    subroutine write_NSCBC_run_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit,NML=NSCBC_run_pars)
!
    endsubroutine write_NSCBC_run_pars
!***********************************************************************
    subroutine parse_nscbc(bc,bc1,bc2)
!
!  Parse boundary conditions, which may be in the form `a' (applies to
!  both `lower' and `upper' boundary) or `a:s' (use `a' for lower,
!  `s' for upper boundary.
!
!  Be aware of the difference in format when giving NSCBC boundary
!  conditions and usual boundary conditions through the bcx, bcy, bcz
!  variables:
!
!  bc = 'top_x:bottom_x','top_y:bottom_y','top_z:bottom_z'
!  for top and bottom boundary treatment at x, y and z-boundaries.
!
!  bc1(1) then refers to boundary treatment at bottom x-boundary, bc2(1)
!  at top x-boundary etc.
!  Ie. this routine sets the boundary condition variables, bc1 and bc2,
!  for x, y and z-boundaries all at once.
!
!   7-jul-08/arne: adapted from parse_bc
!
      character (len=2*nscbc_len+1), dimension(3) :: bc
      character (len=nscbc_len), dimension(3) :: bc1,bc2
      integer :: j,isep
!
      intent(in) :: bc
      intent(out) :: bc1,bc2
!
      do j=1,3
        isep = index(bc(j),':')
        if (isep > 0) then
          bc1(j) = bc(j)(1:isep-1)
          bc2(j) = bc(j)(isep+1:)
        else
          bc1(j) = bc(j)(1:nscbc_len)
          bc2(j) = bc(j)(1:nscbc_len)
        endif
      enddo
!
    endsubroutine
!***********************************************************************
    subroutine NSCBC_clean_up
!
!  Deallocate all allocatable arrays
!
      if (allocated(f_in)) deallocate(f_in)
      if (allocated(x_in)) deallocate(x_in)
      if (allocated(y_in)) deallocate(y_in)
      if (allocated(z_in)) deallocate(z_in)
!
    endsubroutine NSCBC_clean_up
!***********************************************************************
    subroutine find_velocity_at_inlet(u_in,non_zero_transveral_velo,&
        domain_length,grid_points,u_t,direction,imin,imax,jmin,jmax)
!
!  Find velocity at inlet.
!
!  2010.01.20/Nils Erland L. Haugen: coded
!
      logical, intent(out) :: non_zero_transveral_velo
      real, dimension(:,:,:), intent(out) :: u_in
      real, intent(in) :: domain_length,u_t
      integer, intent(in) :: grid_points,direction
      integer, intent(in) :: imin,imax,jmin,jmax
!
      real :: shift, grid_shift, weight, round
      integer :: iround,lowergrid,uppergrid,ii
      real, dimension(3) :: velo,tmp
      real, dimension(2) :: radius,theta
      real :: radius_mean, velocity_ratio,An,smooth,rad
      real, dimension (3) :: jet_inner_diameter,jet_outer_diameter
      real, dimension (2) :: jet_center, jet_velocity
      integer :: j,kkk,jjj
!
!  First we check if we are using a pre-run data file as inlet
!  condition, if not the chosen inlet profile will be used.
!
        if (inlet_from_file) then
          non_zero_transveral_velo=.true.
          if (domain_length == 0) call fatal_error('find_velocity_at_inlet',&
              'domain_length=0. Check that the precisions are the same.')
          round=t*u_t/domain_length
          iround=int(round)
          shift=round-iround
          grid_shift=shift*grid_points
          lowergrid=l1_in+int(grid_shift)
          uppergrid=lowergrid+1
          weight=grid_shift-int(grid_shift)
!
!  Do we want a smooth start
!
          if (smooth_time .gt. 0) then
            smooth=min(t/smooth_time,1.)
          else
            smooth=1.
          endif
!
!  Set the turbulent inlet velocity
!
          if (direction==1) then
            call turbulent_vel_x(u_in,lowergrid,imin,imax,jmin,jmax,weight,smooth)
          elseif(direction==2) then
            call turbulent_vel_y(u_in,lowergrid,imin,imax,jmin,jmax,weight,smooth)
          elseif(direction==3) then
            call turbulent_vel_z(u_in,lowergrid,imin,imax,jmin,jmax,weight,smooth)
          endif
!
!  Add the mean inlet velocity to the turbulent one
!
          u_in(:,:,direction)=u_in(:,:,direction)+u_t
        else
!
! Define velocity profile at inlet
!
          u_in=0
          do j=1,ninit
            select case (inlet_profile(j))
!
            case ('nothing')
              if (lroot .and. it==1 .and. j == 1 .and. lfirst) &
                  print*,'inlet_profile: nothing'
              non_zero_transveral_velo=.false.
!
            case ('uniform')
              if (lroot .and. it==1 .and. lfirst) &
                  print*,'inlet_profile: uniform'
              non_zero_transveral_velo=.false.
              u_in(:,:,direction)=u_in(:,:,direction)+u_t
!
            case ('coaxial_jet')
              if (lroot .and. it==1 .and. lfirst) &
                  print*,'inlet_profile: coaxial_jet'
              non_zero_transveral_velo=.true.
              velocity_ratio=3.3
              velo(1)=u_t
              velo(2)=velo(1)*velocity_ratio
              velo(3)=0.04*velo(2)
              radius(1)=0.0182
              radius(2)=radius(1)*2.
              radius_mean=(radius(1)+radius(2))/2.
              theta(1)=radius(1)/13.
              theta(2)=radius(2)/20.
              jet_center(1)=0
              jet_center(2)=0

              do jjj=imin,imax
                do kkk=jmin,jmax
                  rad=sqrt(&
                      (y(jjj)-jet_center(1))**2+&
                      (z(kkk)-jet_center(2))**2)
                  ! Add mean velocity profile
                  if (rad < radius_mean) then
                    u_in(jjj-imin+1,kkk-jmin+1,1)=u_in(jjj-imin+1,kkk-jmin+1,1)&
                        +(velo(1)+velo(2))/2&
                        +(velo(2)-velo(1))/2*tanh((rad-radius(1))/(2*theta(1)))
                  else
                    u_in(jjj-imin+1,kkk-jmin+1,1)=u_in(jjj-imin+1,kkk-jmin+1,1)&
                        +(velo(2)+velo(3))/2&
                        +(velo(3)-velo(2))/2*tanh((rad-radius(2))/(2*theta(2)))
                  endif
                enddo
              enddo
            end select
!            
          enddo
        endif
!
      end subroutine find_velocity_at_inlet
!***********************************************************************
      subroutine turbulent_vel_x(u_in,lowergrid,imin,imax,jmin,jmax,weight,smooth)
!
!  Set the turbulent inlet velocity
!
!  2010.01.21/Nils Erland: coded
!
        real, dimension(ny,nz,3), intent(out) :: u_in
        integer, intent(in) :: lowergrid,imin,imax,jmin,jmax
        real, intent(in) :: weight,smooth
!
        u_in(:,:,:)&
            =(f_in(lowergrid,imin:imax,jmin:jmax,iux:iuz)*(1-weight)&
            +f_in(lowergrid+1,imin:imax,jmin:jmax,iux:iuz)*weight)*smooth
!
      end subroutine turbulent_vel_x
!***********************************************************************
      subroutine turbulent_vel_y(u_in,lowergrid,imin,imax,jmin,jmax,weight,smooth)
!
!  Set the turbulent inlet velocity
!
!  2010.01.21/Nils Erland: coded
!
        real, dimension(nx,nz,3), intent(out) :: u_in
        integer, intent(in) :: lowergrid,imin,imax,jmin,jmax
        real, intent(in) :: weight,smooth
!
        u_in(:,:,:)&
            =(f_in(imin:imax,lowergrid,jmin:jmax,iux:iuz)*(1-weight)&
            +f_in(imin:imax,lowergrid+1,jmin:jmax,iux:iuz)*weight)*smooth
!
      end subroutine turbulent_vel_y
!***********************************************************************
      subroutine turbulent_vel_z(u_in,lowergrid,imin,imax,jmin,jmax,weight,smooth)
!
!  Set the turbulent inlet velocity
!
!  2010.01.21/Nils Erland: coded
!
        real, dimension(nx,ny,3), intent(out) :: u_in
        integer, intent(in) :: lowergrid,imin,imax,jmin,jmax
        real, intent(in) :: weight,smooth
!
        u_in(:,:,:)&
            =(f_in(imin:imax,jmin:jmax,lowergrid,iux:iuz)*(1-weight)&
            +f_in(imin:imax,jmin:jmax,lowergrid+1,iux:iuz)*weight)*smooth
!
      end subroutine turbulent_vel_z
!***********************************************************************
      subroutine get_thermodynamics(mu1,grad_mu1,gamma,cs2,cs,rho0,TT,P0,nu,&
          grad_rho,grad_P,grad_T,lll,sgn,direction,fslice)
!
!  Find thermodynamical quantities, including density and temperature
!
! 2010.01.21/Nils Erland: coded
!
        Use Chemistry
        use Viscosity
        use EquationOfState, only: cs0, cs20      
!
        integer, intent(in) :: direction, sgn,lll
        real, dimension(:,:), intent(out)  :: mu1,cs2,cs,gamma, grad_mu1
        real, dimension(:,:), intent(out)  :: rho0,TT,P0
        real, dimension(:,:,:), intent(inout)  :: grad_rho,grad_T,grad_P
        real, dimension(:,:,:), intent(in) :: fslice
        real, intent(out) :: nu
!
        integer :: i
!
!  Find density
!
      if (ldensity_nolog) then
        rho0 = fslice(:,:,irho)
      else
        rho0 = exp(fslice(:,:,ilnrho))
      endif
!
!  Find temperature
!
      if (iTT>0) then
        TT = fslice(:,:,iTT)
      elseif (ilnTT>0) then
        TT = exp(fslice(:,:,ilnTT))
      endif
!
!  Get viscoity
!
      call getnu(nu)
!        
!  Find mu1, grad_mu1 and gamma
!
        if (ilnTT>0 .or. iTT>0) then
          call get_mu1_slice(mu1,grad_mu1,lll,sgn,direction)
          call get_gamma_slice(gamma,direction,lll)
        else
          gamma=1.
        endif
!
!  Set arrays for the speed of sound and for the speed of sound squared (is it
!  really necessarry to have both arrays?) 
!  Set prefactors to be used later.
!
      if (leos_idealgas) then
        cs2=cs20
        cs=cs0
      elseif (leos_chemistry) then
        call get_cs2_slice(cs2,direction,lll)
        cs=sqrt(cs2)
      else
        print*,"bc_nscbc_prf_x: leos_idealgas=",leos_idealgas,"."
        print*,"bc_nscbc_prf_x: leos_chemistry=",leos_chemistry,"."
        print*,"NSCBC boundary treatment only implemented for ideal gas or" 
        print*,"chemistry. Boundary treatment skipped."
        return
      endif
!
!  Find gradient of rho and temperature
!
      if (.not. ldensity_nolog) then
        do i=1,3
          grad_rho(:,:,i)=grad_rho(:,:,i)*rho0
        enddo
      endif
      if (.not. ltemperature_nolog .and. ilnTT>0) then
        do i=1,3
          grad_T(:,:,i)=grad_T(:,:,i)*TT
        enddo
      endif
!
!  Find pressure and the gradient of pressure
!
      do i=1,3
        if (ilnTT>0) then 
          grad_P(:,:,i)&
              =grad_rho(:,:,i)*TT*Rgas*mu1&
              +grad_T(:,:,i)*rho0*Rgas*mu1&
              +Rgas*grad_mu1*TT*rho0
          P0=rho0*Rgas*mu1*TT
        else
          grad_P(:,:,i)=grad_rho(:,:,i)*cs2
          P0=rho0*cs2
        endif
      enddo
!
    end subroutine get_thermodynamics
!***********************************************************************
      subroutine derivate_boundary(f,sgn,dir,lll,dui_dxj,grad_T,grad_rho)
!
!  Find all derivatives at the boundary
!
!  2010.01.21/Nils Erland: coded
!
        use Deriv, only: der_onesided_4_slice, der_pencil, der2_pencil
!
        integer, intent(in) :: sgn,dir,lll
        real, dimension(:,:,:,:), intent(out) :: dui_dxj
        real, dimension(:,:,:)  , intent(out) :: grad_T,grad_rho
        real, dimension (mx,my,mz,mfarray), intent(in) :: f
!
!        real, dimension (my,mz) :: tmp1,tmp2,tmp3,tmp_lnrho
        real, dimension (:,:), allocatable :: tmp1,tmp2,tmp3,tmp_lnrho
        integer :: i,stat
!
!  Allocate arrays
!
      if (dir == 1) then
        allocate(tmp1(my,mz),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp1 ")        
        allocate(tmp2(my,mz),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp2 ")        
        allocate(tmp3(my,mz),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp3 ")        
        allocate(tmp_lnrho(my,mz),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp_lnrho ")   
      elseif (dir == 2) then
        allocate(tmp1(mx,mz),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp1 ")        
        allocate(tmp2(mx,mz),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp2 ")        
        allocate(tmp3(mx,mz),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp3 ")        
        allocate(tmp_lnrho(mx,mz),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp_lnrho ")    
      elseif (dir == 3) then
        allocate(tmp1(mx,my),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp1 ")        
        allocate(tmp2(mx,my),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp2 ")        
        allocate(tmp3(mx,my),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp3 ")        
        allocate(tmp_lnrho(mx,my),STAT=stat)
        if (stat>0) call stop_it("Couldn't allocate memory for tmp_lnrho ")   
      else
        call fatal_error('bc_nscbc_prf_x','No such dir!')
      endif        
!
!  Initialize arrays
!    
        dui_dxj =0
        grad_rho=0  
!
!  Find the derivatives in the direction normal to the boudary by 
!  one-sided stencils
!
        call der_onesided_4_slice(f,sgn,ilnrho,grad_rho(:,:,dir),lll,dir)
        call der_onesided_4_slice(f,sgn,iux,dui_dxj(:,:,1,dir),lll,dir)
        call der_onesided_4_slice(f,sgn,iuy,dui_dxj(:,:,2,dir),lll,dir)
        call der_onesided_4_slice(f,sgn,iuz,dui_dxj(:,:,3,dir),lll,dir)
        if (ilnTT>0 .or. iTT>0) then
          call der_onesided_4_slice(f,sgn,ilnTT,grad_T(:,:,dir),lll,dir)
        endif
!
!  Do central differencing in the directions parallell to the boundary 
!
        if (dir == 1) then
          if (nygrid /= 1) then
            do i=n1,n2
              call der_pencil(2,f(lll,:,i,iux),tmp1(:,i))
              call der_pencil(2,f(lll,:,i,iuy),tmp2(:,i))
              call der_pencil(2,f(lll,:,i,iuz),tmp3(:,i))
              call der_pencil(2,f(lll,:,i,ilnrho),tmp_lnrho(:,i))
            enddo
            dui_dxj(:,:,1,2)=tmp1(m1:m2,n1:n2)
            dui_dxj(:,:,2,2)=tmp2(m1:m2,n1:n2)
            dui_dxj(:,:,3,2)=tmp3(m1:m2,n1:n2)
            grad_rho(:,:,2)=tmp_lnrho(m1:m2,n1:n2)
          endif
          if (nzgrid /= 1) then
            do i=m1,m2
              call der_pencil(3,f(lll,i,:,iux),tmp1(i,:))
              call der_pencil(3,f(lll,i,:,iuy),tmp2(i,:))
              call der_pencil(3,f(lll,i,:,iuz),tmp3(i,:))
              call der_pencil(3,f(lll,i,:,ilnrho),tmp_lnrho(i,:))
            enddo
            dui_dxj(:,:,1,3)=tmp1(m1:m2,n1:n2)
            dui_dxj(:,:,2,3)=tmp2(m1:m2,n1:n2)
            dui_dxj(:,:,3,3)=tmp3(m1:m2,n1:n2)
            grad_rho(:,:,3)=tmp_lnrho(m1:m2,n1:n2)
          endif
        elseif (dir == 2) then
          if (nxgrid /= 1) then
            do i=n1,n2
              call der_pencil(1,f(:,lll,i,iux),tmp1(:,i))
              call der_pencil(1,f(:,lll,i,iuy),tmp2(:,i))
              call der_pencil(1,f(:,lll,i,iuz),tmp3(:,i))
              call der_pencil(1,f(:,lll,i,ilnrho),tmp_lnrho(:,i))
            enddo
            dui_dxj(:,:,1,1)=tmp1(l1:l2,n1:n2)
            dui_dxj(:,:,2,1)=tmp2(l1:l2,n1:n2)
            dui_dxj(:,:,3,1)=tmp3(l1:l2,n1:n2)
            grad_rho(:,:,1)=tmp_lnrho(l1:l2,n1:n2)
          endif
          if (nzgrid /= 1) then
            do i=l1,l2
              call der_pencil(3,f(i,lll,:,iux),tmp1(i,:))
              call der_pencil(3,f(i,lll,:,iuy),tmp2(i,:))
              call der_pencil(3,f(i,lll,:,iuz),tmp3(i,:))
              call der_pencil(3,f(i,lll,:,ilnrho),tmp_lnrho(i,:))
            enddo
            dui_dxj(:,:,1,3)=tmp1(l1:l2,n1:n2)
            dui_dxj(:,:,2,3)=tmp2(l1:l2,n1:n2)
            dui_dxj(:,:,3,3)=tmp3(l1:l2,n1:n2)
            grad_rho(:,:,3)=tmp_lnrho(l1:l2,n1:n2)
          endif
        elseif (dir == 3) then
          if (nxgrid /= 1) then
            do i=m1,m2
              call der_pencil(1,f(:,i,lll,iux),tmp1(:,i))
              call der_pencil(1,f(:,i,lll,iuy),tmp2(:,i))
              call der_pencil(1,f(:,i,lll,iuz),tmp3(:,i))
              call der_pencil(1,f(:,i,lll,ilnrho),tmp_lnrho(:,i))
            enddo
            dui_dxj(:,:,1,1)=tmp1(l1:l2,m1:m2)
            dui_dxj(:,:,2,1)=tmp2(l1:l2,m1:m2)
            dui_dxj(:,:,3,1)=tmp3(l1:l2,m1:m2)
            grad_rho(:,:,1)=tmp_lnrho(l1:l2,m1:m2)
          endif
          if (nygrid /= 1) then
            do i=m1,m2
              call der_pencil(2,f(:,i,lll,iux),tmp1(:,i))
              call der_pencil(2,f(:,i,lll,iuy),tmp2(:,i))
              call der_pencil(2,f(:,i,lll,iuz),tmp3(:,i))
              call der_pencil(2,f(:,i,lll,ilnrho),tmp_lnrho(:,i))
            enddo
            dui_dxj(:,:,1,2)=tmp1(l1:l2,m1:m2)
            dui_dxj(:,:,2,2)=tmp2(l1:l2,m1:m2)
            dui_dxj(:,:,3,2)=tmp3(l1:l2,m1:m2)
            grad_rho(:,:,2)=tmp_lnrho(l1:l2,m1:m2)
          endif
        endif
!
      end subroutine derivate_boundary
!***********************************************************************
      subroutine transversal_terms(T_1,T_2,T_3,T_4,T_5,rho0,P0,gamma,&
          fslice,grad_rho,grad_P,dui_dxj,dir1,dir2,dir3)
!
!  Find the transversal terms.
!  This correspond to the T's in Lodato et al. JCP (2008)
!
!  2010.01.21/Nils Erland: coded
!
        integer,                  intent(in) :: dir1,dir2,dir3
        real, dimension(:,:),     intent(out):: T_1, T_2, T_3, T_4, T_5
        real, dimension(:,:),     intent(in) :: rho0,P0,gamma
        real, dimension(:,:,:),   intent(in) :: fslice,grad_rho,grad_P
        real, dimension(:,:,:,:), intent(in) :: dui_dxj 
!
!  Calculate the T's
!
        T_1= rho0*dui_dxj(:,:,dir2,dir2)+fslice(:,:,dir2)*grad_rho(:,:,dir2)&
            +rho0*dui_dxj(:,:,dir3,dir3)+fslice(:,:,dir3)*grad_rho(:,:,dir3)
        T_2= fslice(:,:,dir2)*dui_dxj(:,:,dir1,dir2)&
            +fslice(:,:,dir3)*dui_dxj(:,:,dir1,dir3)
        T_3= fslice(:,:,dir2)*dui_dxj(:,:,dir2,dir2)&
            +fslice(:,:,dir3)*dui_dxj(:,:,dir2,dir3)&
            +grad_P(:,:,dir2)/rho0
        T_4= fslice(:,:,dir2)*dui_dxj(:,:,dir3,dir2)&
            +fslice(:,:,dir3)*dui_dxj(:,:,dir3,dir3)&
            +grad_P(:,:,dir3)/rho0
        T_5= fslice(:,:,dir2)*grad_P(:,:,dir2)&
            +fslice(:,:,dir3)*grad_P(:,:,dir3)&
            +gamma*P0*(dui_dxj(:,:,dir2,dir2)+dui_dxj(:,:,dir3,dir3))
!
      end subroutine transversal_terms
!***********************************************************************
endmodule NSCBC
