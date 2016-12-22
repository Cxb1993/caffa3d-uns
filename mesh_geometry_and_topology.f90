!
! Module for geometry definition on unstructured meshes.
!
module geometry

use types
use utils, only: get_unit, file_row_count, r8vec_print_some, i4vec_print2

implicit none

! General mesh data
integer :: numNodes                           ! no. of nodes in mesh
integer :: numCells                           ! no. of cells in the mesh
integer :: numFaces                           ! no. of INNER+BOUNDARY faces in the mesh
integer :: numInnerFaces                      ! no. of INNER cells faces in the mesh
integer :: numBoundaryFaces                   ! self explanatory
integer :: numTotal                           ! number of volume field values + number of boundary field values numCells+numBoundaryFaces
integer :: nnz                                ! no.of nonzeros

integer :: ninl,nout,nsym,npru,nwal,noc, &
           nwalm,nwali,nwala,nwalf

integer :: iInletStart
integer :: iOutletStart
integer :: iSymmetryStart
integer :: iWallStart
integer :: iPressOutletStart
integer :: iOCStart

integer :: iInletFacesStart
integer :: iOutletFacesStart
integer :: iSymmetryFacesStart
integer :: iWallFacesStart
integer :: iPressOutletFacesStart
integer :: iOCFacesStart

integer, parameter :: nomax = 24              ! Max no. of nodes in face - determines size of some arrays, just change this if necessary.

logical :: native_mesh_files

integer :: points_file, faces_file, owner_file, neighbour_file, boundary_file ! file units



! Mesh geometry

! Geometry parameters defined for mesh nodes [1:numNodes]
real(dp), dimension(:), allocatable :: x ,y ,z  ! Coordinates of mesh nodes 

! Geometry parameters defined cellwise [1:numCells]:
real(dp), dimension(:), allocatable :: xc,yc,zc     ! Coordinates of cell centers
real(dp), dimension(:), allocatable :: vol          ! Cell volume
real(dp), dimension(:), allocatable :: wallDistance ! Distance to the nearest wall - needed in some turb. models

! Geometry parameters defined for all (inner+boundary) cell faces [1:numFaces]
real(dp), dimension(:), allocatable :: arx, ary, arz   ! Cell face area x-, y- and z-component 
real(dp), dimension(:), allocatable :: xf, yf, zf      ! Coordinates of cell face center

! Geometry parameters defined for all inner cell faces [1:numInnerFaces]
real(dp), dimension(:), allocatable :: xpp, ypp, zpp   ! Coordinates of auxilliary points - owner cell 
real(dp), dimension(:), allocatable :: xnp, ynp, znp   ! Coordinates of auxilliary points - neighbour cell 
real(dp), dimension(:), allocatable :: facint          ! Interpolation factor 
!real(dp), dimension(:), allocatable :: dpn            ! Distance between neigbor cell centers [1:numInnerFaces]

! Geometry parameters defined for boundary faces

real(dp), dimension(:), allocatable :: srds,dns    ! srds = |are|/|dns|, dns = normal distance to cell center from face |dpn*face_normal_unit_vec|
real(dp), dimension(:), allocatable :: srdw,dnw    ! srdw = |are|/|dnw|, dnw = normal distance to cell center from face |dpn*face_normal_unit_vec|
real(dp), dimension(:), allocatable :: srdoc          ! srdoc = |are|/|dpn*face_normal_unit_vec| 
real(dp), dimension(:), allocatable :: foc            ! Interpolation factor for faces at block boundaries (known as o-c- faces in structured code)

! Mesh topology information - connectivity of cells trough faces
integer, dimension(:), allocatable :: owner     ! Index of the face owner cell
integer, dimension(:), allocatable :: neighbour ! Index of the neighbour cell  - it shares the face with owner
integer, dimension(:), allocatable :: ijl, ijr  ! left and right cell at the block boundary, it is still an inner face in the domain


public 

contains


pure integer function noel(NTYPE)
!
! Number of nodes in element of NTYPE type of element
!
 implicit none
 integer, intent(in) :: NTYPE
 integer, parameter :: noel_NTYPE1 = 2 ! no. of nodes in element-here Line
 integer, parameter :: noel_NTYPE2 = 3 ! no. of nodes in element-here Tri
 integer, parameter :: noel_NTYPE3 = 4 ! no. of nodes in element-here Quad
 integer, parameter :: noel_NTYPE4 = 4 ! no. of nodes in element-here Tet
 integer, parameter :: noel_NTYPE5 = 8 ! no. of nodes in element-here Hex
 integer, parameter :: noel_NTYPE6 = 6 ! no. of nodes in element-here Prism
 integer, parameter :: noel_NTYPE7 = 5 ! no. of nodes in element-here Pyramid
 

 if(NTYPE.eq.1) then ! -> Cappuccino line
   noel = noel_NTYPE1 
 elseif(NTYPE.eq.2) then ! -> Cappuccino Tri
   noel = noel_NTYPE2 
 elseif(NTYPE.eq.3) then ! -> Cappuccino Quad
   noel = noel_NTYPE3 
 elseif(NTYPE.eq.4) then ! -> Cappuccino Tet
   noel = noel_NTYPE4 
 elseif(NTYPE.eq.5) then ! -> Cappuccino Hex
   noel = noel_NTYPE5 
 elseif(NTYPE.eq.6) then ! -> Cappuccino Prism
   noel = noel_NTYPE6 
 elseif(NTYPE.eq.7) then ! -> Cappuccino Pyramid
   noel = noel_NTYPE7 
 else
   noel = 0
 endif

end function


subroutine triangular_face_area_components_polymesh(px,py,pz,qx,qy,qz,nx,ny,nz)
!
! Ai, i=1,n are n triangular faces enclosing polyhedron P.
! Vertices of Ai are (ai,bi,ci),
!                                _    _   _    _     _  _    _  _
! Unit normal to P on each Ai is ni = ni/|ni|, ni = (bi-ai)x(ci-ai)
! and 
! _    _  _    _    _  _
! p = (bi-ai); q = (ci-ai)
!
! Finally:              _
! Area A of Ai, A = 1/2|ni|
!
! Sources: 
! [1] Dr Robert Nurnberg, Imperial College London, www.ma.ic.ac.uk/~rn/centroid.pdf
! [2] paulbourke.net/geometry/polygonmesh
!
  implicit none
  real(dp), intent(in) :: px,py,pz,qx,qy,qz
  real(dp), intent(inout) :: nx,ny,nz

  ! real(dp), parameter :: half = 0.5_dp

  ! Cross products for triangle surface vectors
  nx = py*qz-pz*qy
  ny = pz*qx-px*qz
  nz = px*qy-py*qx

end subroutine


pure function cell_volume_part_polymesh(ax,ay,az,nx,ny,nz) result(volume_part)
!
! Ai, i=1,n are n triangular faces enclosing polyhedron P.
! Vertices of Ai are (ai,bi,ci),
!                                _    _   _    _
! Unit normal to P on each Ai is ni = ni/|ni|, ni = (bi-ai)x(ci-ai)
! Volume of P is given by:
!                         _  _                     _  _ 
!    V = 1/6 * sum_i=1^n (ai.ni) or sum_i=1^n 1/6*(ai.ni)
!
! Sources: 
! [1] Dr Robert Nurnberg, Imperial College London, www.ma.ic.ac.uk/~rn/centroid.pdf
! [2] paulbourke.net/geometry/polygonmesh

  implicit none
  real(dp), intent(in) :: ax,ay,az
  real(dp), intent(in) :: nx,ny,nz
  real(dp) :: volume_part

  volume_part = 1./6._dp*( ax*nx + ay*ny + az*nz )
end function


pure function centroid_component_part_polymesh(ax,bx,cx,nx,vol) result(cc_part)
!
! Ai, i=1,n are n triangular faces enclosing polyhedron P.
! Vertices of Ai are (ai,bi,ci),
!                                _    _   _    _
! Unit normal to P on each Ai is ni = ni/|ni|, ni = (bi-ai)x(ci-ai)
! Cell center (cc) component of P is given by:
!                                  
!    cc.ed = 1/2V * sum_i=1^n (x.ed)^2*(ni.ed), where ed is unit basis of R^3, d=1,2,3.
!
! Thios function calculates part under summation which is accumulated in outer loop. 
!
! Sources: 
! [1] Dr Robert Nurnberg, Imperial College London, www.ma.ic.ac.uk/~rn/centroid.pdf
! [2] paulbourke.net/geometry/polygonmesh

  implicit none
  real(dp), intent(in) :: ax,bx,cx
  real(dp), intent(in) :: vol,nx
  real(dp) :: cc_part

  cc_part = 1./(2*vol) * 1./24._dp*nx * ( (ax+bx)**2 + (bx+cx)**2 + (cx+ax)**2 )

end function  


  function determinant(a1,a2,a3,b1,b2,b3,q1,q2,q3)
!
! Calculates determinant of 3x3 matrix
!
  implicit none
  real(dp) :: a1,a2,a3,b1,b2,b3,q1,q2,q3
  real(dp) :: determinant

  determinant = (a2*b3-b2*a3)*q1 &
               +(b1*a3-a1*b3)*q2 &
               +(a1*b2-a2*b1)*q3
  end function



subroutine find_intersection_point( &
!                     plane defined by face corner, bottom and south:
                       x1,y1,z1,&
                       x2,y2,z2, &
                       x3,y3,z3, &
!                      line defined by cell center and neighbour center:
                       x4,y4,z4, &
                       x5,y5,z5, &
!                      intersection point (output):
                       xjp,yjp,zjp &
                       )
!
!***********************************************************************
! Find intersection point (pjp={xjp,yjp,zjp}) of 
! plane (defined by points p1={x1,y1,z1}, p2={x2,y2,z2} and p3={x3,y3,z3}),
! and line (defined by points p4={x4,y4,z4} and p5={x5,y5,z5}).
! The intersection point j' is not the face center j on non-orthogonal meshes.
! There is an "intersection point offset" |jj'| which determines the level
! of nonorthogonality.
!
!
!       |1  1  1  1 |     |1  1  1  0    |
! t = - |x1 x2 x3 x4|  /  |x1 x2 x3 x5-x4|  (mind the minus sign!)
!       |y1 y2 y3 y4| /   |y1 y2 y3 y5-y4|
!       |z1 z2 z3 z4|     |z1 z2 z3 z5-z4|
!
! And intersection point is given by:
! xj = x4 +(x5-x4)*t
! yj = y4 +(y5-y4)*t
! zj = z4 +(z5-z4)*t
!
!
! Nikola Mirkov @2016
!
! example usage: 
! call find_intersection_point( &
!!                            plane defined by face corner, bottom and south:
!                             x(inp),y(inp),z(inp),&
!                             x(inp-idns),y(inp-idns),z(inp-idns), &
!                             x(inp-idtb),y(inp-idtb),z(inp-idtb), &
!!                            line defined by cell center and neighbour center:
!                             xc(inp),yc(inp),zc(inp), &
!                             xc(inp+idew),yc(inp+idew),zc(inp+idew), &
!!                            intersection point:
!                             xj,yj,zj &
!                             )
!***********************************************************************
  implicit none 
!
!***********************************************************************
!

  real(dp), intent(in) :: x1,y1,z1,&
                          x2,y2,z2, &
                          x3,y3,z3, &
                          x4,y4,z4, &
                          x5,y5,z5
  real(dp), intent(inout) :: xjp,yjp,zjp

  real(dp) :: t

 ! Produced by MATLAB symbolic tool.
 t =-(x2*(y3*z4-y4*z3)-x1*(y3*z4-y4*z3)-x3*(y2*z4-y4*z2)+x1*(y2*z4-y4*z2)+x3*(y1*z4-y4*z1)-x2* &
     (y1*z4-y4*z1)+x4*(y2*z3-y3*z2)-x1*(y2*z3-y3*z2)-x4*(y1*z3-y3*z1)+x2*(y1*z3-y3*z1)+x4* &
     (y1*z2-y2*z1)-x3*(y1*z2-y2*z1)) &
    /(x2*(y3*(z5-z4)-(y5-y4)*z3)-x1*(y3*(z5-z4)-(y5-y4)*z3)-x3*(y2*(z5-z4)-(y5-y4)*z2)+x1* &
     (y2*(z5-z4)-(y5-y4)*z2)+x3*(y1*(z5-z4)-(y5-y4)*z1)-x2*(y1*(z5-z4)-(y5-y4)*z1)+(x5-x4)* &
     (y2*z3-y3*z2)-(x5-x4)*(y1*z3-y3*z1)+(x5-x4)*(y1*z2-y2*z1))

  xjp = x4 +(x5-x4)*t
  yjp = y4 +(y5-y4)*t
  zjp = z4 +(z5-z4)*t

end subroutine


subroutine read_line_faces_file_polyMesh(faces_file,nn,nod,nmax)
  implicit none
  integer, intent(in) :: faces_file
  integer, intent(in) :: nmax
  integer, intent(out) :: nn
  integer, dimension(nmax), intent(out) :: nod
  integer :: j,m,n
  character(len=15) :: char_string,char_string2

    nn = 0
    nod(:) = 0

    ! Read how many nodes in face
    read(faces_file,'(a)') char_string
    read(char_string(1:1),*)j
    backspace(faces_file)

      read(faces_file,*) char_string,nod(2:j-1),char_string2

      ! Char to double conversion:
      read(char_string(1:1),*)j                ! number of vertrices
      read(char_string(3:),*) m                ! first vertex
      read(char_string2(1:len_trim(char_string2)-1),*) n ! last vertex

      nn = j
      nod(1) = m + 1
      nod(2:j-1) = nod(2:j-1) + 1
      nod(nn) = n + 1

end subroutine



subroutine mesh_geometry
!
!  Description:
!    Calculates basic geometrical quantities of numerical mesh
!    defined in this module and needed for FVM computation.
!    Mesh is described in files similar to polyMesh format.
!    Mesh files are 'points', 'faces', 'owner, 'neighbour', 'boundary'
!
!  Date:
!    26/11/2015
!
!  Author:
!    Nikola Mirkov nmirkov@vinca.rs
!
  implicit none

! Locals
  integer :: i,j,k,l
  integer :: iface

  integer :: inp,inn

  character(len=1) :: ch
  character(len=15) :: char_string,char_string2
  character(len=80) :: line_string

  integer, dimension(nomax) :: node  ! It will store global node numbers of cell vertexes
  integer :: nnodes                ! no. of nodes in face

  integer :: numBoundaries,bctype,nfaces,startFace

  real(dp), parameter :: half = 0.5_dp
  real(dp), parameter :: one_third = 1._dp/3._dp

  real(dp) :: px,py,pz, qx,qy,qz, ax,ay,az, nx,ny,nz, cx,cy,cz
  real(dp) :: xpn,ypn,zpn
  real(dp) :: xjp,yjp,zjp
  real(dp) :: dpn,djn
 

!
! > OPEN polyMesh format files: 'points', 'faces', 'owner', 'neighbour'.
!

  call get_unit( points_file )
  open( unit = points_file,file = 'polyMesh/points' )
  rewind points_file

  call get_unit( faces_file )
  open( unit = faces_file, file='polyMesh/faces' )
  rewind faces_file

  call get_unit( owner_file )
  open( unit = owner_file, file='polyMesh/owner' )
  rewind owner_file

  call get_unit( neighbour_file )
  open( unit = neighbour_file, file='polyMesh/neighbour' )
  rewind neighbour_file

  call get_unit( boundary_file )
  open( unit = boundary_file, file='polyMesh/boundary' )
  rewind boundary_file


  native_mesh_files = .true.

  ! First characters in OpenFOAM polyMesh files is comment '/*'
  read(points_file,'(a)') ch
  backspace(points_file)
  if(ch == '/')  native_mesh_files = .false.

!
! > Find out number of faces belonging to a specific boundary condition.
! 
  ! Initialize number of boundary faces for each boundary type 
  ninl = 0 
  nout = 0
  nsym = 0
  nwal = 0
  npru = 0
  noc = 0

  ! Different types of walls: moving, isothermal, adiabatic, flux.
  nwalm = 0
  nwali = 0
  nwala = 0
  nwalf = 0

  read(boundary_file,'(a)') line_string
  read(boundary_file,'(i1)') numBoundaries

  do i=1,numBoundaries
  read(boundary_file,*) bctype,nfaces,startFace

    select case (bctype)

      case (1)
        if (ninl==0) iInletFacesStart = startFace
        ninl = ninl + nfaces

      case (2)
        if (nout==0) iOutletFacesStart = startFace
        nout = nout + nfaces

      case (3)
        if (nsym==0) iSymmetryFacesStart = startFace
        nsym = nsym + nfaces

      case (4)
        if (nwal==0) iWallFacesStart = startFace
        nwal = nwal + nfaces

      case (41)
        if (nwal==0) iWallFacesStart = startFace
        nwal = nwal + nfaces
        nwalm = nwalm + nfaces

      case (42)
        if (nwal==0) iWallFacesStart = startFace
        nwal = nwal + nfaces
        nwali = nwali + nfaces

      case (43)
        if (nwal==0) iWallFacesStart = startFace
        nwal = nwal + nfaces
        nwala = nwala + nfaces

      case (44)
        if (nwal==0) iWallFacesStart = startFace
        nwal = nwal + nfaces
        nwalf = nwalf + nfaces

      case (5)
        if (npru==0) iPressOutletFacesStart = startFace
        npru = npru + nfaces

      case (6)
        if (noc==0) iOCFacesStart = startFace
        noc = noc + nfaces

      case default
        write(*,*) "Non-existing boundary type in polymesh/boundary file!"
        stop

    end select 

  enddo  


!
! > Find out numNodes, numFaces, numInnerFaces, etc.
! 

if (native_mesh_files)  then

    ! 'owner' file
    read(owner_file,*) numNodes
    read(owner_file,*) numCells
    read(owner_file,*) numFaces
    read(owner_file,*) numInnerFaces


  else 
  !
  !...if OpenFOAM polyMesh format- the essence of what can be found in polyMeshToCappuccino code.
  ! Code here is tested for OpenFOAM version 4.0, if they don't change polyMesh format this should be OK.
  !       


    ! 'points' file
    do i=1,16
      read(points_file,*) ch
    end do

    read(points_file,*) numNodes
    read(points_file,*) ch ! reads "("

    k=0
    l=0
    
    ! 'owner' file
    do i=1,17
      if (i==13) then
        read(owner_file,*) char_string,line_string
        do j=12,len_trim(line_string)
          if (line_string(j:j+5)=='nCells') then
            k=j+7
          endif
          if (line_string(j:j+5)=='nFaces') then
            l=j-2
          endif
        end do
        read(line_string(k:l),*) numCells
      else
        read(owner_file,*) ch
      endif
    end do
    read(owner_file,*) numFaces
    read(owner_file,*) ch ! reads "("


    ! 'neighbour' file
    do i=1,17
      read(neighbour_file,*) ch
    end do
    read(neighbour_file,*) numInnerFaces
    read(neighbour_file,*) ch ! reads "("


    ! 'faces' file
    do i=1,18
      read(faces_file,*) ch
    end do

  endif


  ! Number of non-zero elements in sparse matrix: nnz
  nnz = 2*numInnerFaces + numCells

  ! Number of boundary faces
  numBoundaryFaces = numFaces - numInnerFaces

  ! Size of arrays storing variables numCells+numBoundaryFaces
  numTotal = numCells + numBoundaryFaces

  ! Where in variable arrays, the boundary face values are stored, 
  ! e.g. for inlet faces it is: (iInletStart+1, iInletStart+Ninl),
  ! for outlet faces it is: (iOutletStart+1, iOutletStart+Nout) etc.
  ! Having all values of a variable, incuding those of volume field (defined in cell centers)
  ! and those of boundary surface field in a single array is helpful.
  iInletStart = numCells
  iOutletStart = numCells+Ninl
  iSymmetryStart = numCells+Ninl+Nout
  iWallStart = numCells+Ninl+Nout+Nsym
  iPressOutletStart = numCells+Ninl+Nout+Nsym+Nwal
  iOCStart = numCells+Ninl+Nout+Nsym+Nwal+Npru


!
! > Write report on mesh size into log file
!
  write ( *, '(a)' ) ' '
  write ( *, '(a)' ) '  Mesh data: '

  write ( *, '(a)' ) ' '
  write ( *, '(a,i8)' ) '  Number of nodes, numNodes = ', numNodes

  write ( *, '(a)' ) ' '
  write ( *, '(a,i8)' ) '  Number of cells, numCells = ', numCells

  write ( *, '(a)' ) ' '
  write ( *, '(a,i8)' ) '  Number of cell-faces, numFaces = ', numFaces

  write ( *, '(a)' ) ' '
  write ( *, '(a,i8)' ) '  Number of inner cell-faces, numInnerFaces = ', numInnerFaces

  write ( *, '(a)' ) ' '
  write ( *, '(a,i8)' ) '  Number of nonzero coefficients, nnz (= 2*numInnerFaces + numCells)  = ', nnz

  write ( *, '(a)' ) ' '
  write ( *, '(a)' ) '  Boundary information:'
  write ( *, '(a)' ) ' '
  write ( *, '(a,i8)' ) '  Number of cell-faces on boundary, numBoundaryFaces = ', numBoundaryFaces


  if( ninl.gt.0 ) then 
    write ( *, '(a)' ) ' '
    write ( *, '(a,i8)' ) '  Number of inlet faces  = ', ninl
  endif

  if( nout.gt.0 ) then 
    write ( *, '(a)' ) ' '
    write ( *, '(a,i8)' ) '  Number of outlet faces  = ', nout
  endif

  if( nsym.gt.0 ) then
    write ( *, '(a)' ) ' '
    write ( *, '(a,i8)' ) '  Number of symmetry faces  = ', nsym
  endif

  if( nwal.gt.0 ) then
    write ( *, '(a)' ) ' '
    write ( *, '(a,i8)' ) '  Number of wall faces  = ', nwal
    if( nwalm.gt.0 ) then
      write ( *, '(a)' ) ' '
      write ( *, '(4x,a,i8)' ) 'Number of moving wall faces  = ', nwalm
    endif
    if( nwali.gt.0 ) then
      write ( *, '(a)' ) ' '
      write ( *, '(4x,a,i8)' ) 'Number of isothermal wall faces  = ', nwali
    endif
    if( nwala.gt.0 ) then
      write ( *, '(a)' ) ' '
      write ( *, '(4x,a,i8)' ) 'umber of adiabatic wall faces  = ', nwala
    endif
    if( nwalf.gt.0 ) then
      write ( *, '(a)' ) ' '
      write ( *, '(4x,a,i8)' ) 'Number of flux wall faces  = ', nwalf
    endif
  endif

  if( npru.gt.0 ) then
    write ( *, '(a)' ) ' '
    write ( *, '(a,i8)' ) '  Number of pressure-outlet faces  = ', npru
  endif
    
  if( noc.gt.0 ) then
    write ( *, '(a)' ) ' '
    write ( *, '(a,i8)' ) '  Number of O-C- faces  = ', noc
  endif

!
! > Allocate arrays for Mesh description
!

  allocate ( x(numNodes) )
  allocate ( y(numNodes) )
  allocate ( z(numNodes) )

  allocate ( xc(numCells) )
  allocate ( yc(numCells) )
  allocate ( zc(numCells) )

  allocate ( vol(numCells) )

  allocate ( wallDistance(numCells) )

  allocate ( arx(numFaces) )
  allocate ( ary(numFaces) )
  allocate ( arz(numFaces) )

  allocate ( xf(numFaces) )
  allocate ( yf(numFaces) ) 
  allocate ( zf(numFaces) )

  allocate ( facint(numInnerFaces) ) 

  allocate ( owner(numFaces) )
  allocate ( neighbour(numInnerFaces) )

  allocate ( dns(nsym) )      
  allocate ( srds(nsym) )  

  allocate ( dnw(nwal) )      
  allocate ( srdw(nwal) ) 

  allocate ( ijl(noc) ) 
  allocate ( ijr(noc) ) 
  allocate ( srdoc(noc) ) 
  allocate ( foc(noc) )                                     


!
! > Read and process Mesh files 
!

  if (native_mesh_files) then
    
    ! 'points' file
    do i=1,numNodes
        read( points_file, * ) x(i), y(i), z(i) 
    enddo

    ! 'owner' file
    do iface=1,numFaces
      read( owner_file, * ) owner(iface)
    enddo

    ! 'neighbour' file
    do iface=1,numInnerFaces
      read( neighbour_file, * ) neighbour(iface)
    enddo

  else ! OpenFOAM polyMesh format

    ! 'points' file
    do i=1,numNodes
      read(points_file,*) char_string,y(i),char_string2

      ! Char to double conversion:
      read(char_string(2:),*) x(i)
      read(char_string2(1:len_trim(char_string2)-1),*) z(i)  
    end do


    ! 'owner' file
    do i=1,numFaces
      read(owner_file,*) owner(i)
      owner(i) = owner(i) + 1 ! fortran starts from 1
    end do



    ! 'neighbour' file
    do i=1,numInnerFaces
      read(neighbour_file,*) neighbour(i)
      neighbour(i) = neighbour(i) + 1 ! fortran starts from 1
    end do

  endif

  !
  ! > Cell volumes, cell face centers
  !

  do iface=1,numFaces

    inp = owner(iface)

    node(:) = 0

    ! Read line in 'faces' file
    if (native_mesh_files) then
      read( faces_file, * ) nnodes, (node(k), k=1,nnodes)
    else ! OpenFOAM polyMesh
      call read_line_faces_file_polyMesh(faces_file,nnodes,node,nomax)
    endif

    ax = 0.0_dp
    ay = 0.0_dp
    az = 0.0_dp

    do i=1,nnodes-2 
      ! Vectors to vertices
      ! 2-1
      px = x(node(i+1))-x(node(1))
      py = y(node(i+1))-y(node(1))
      pz = z(node(i+1))-z(node(1))
      ! 3-1
      qx = x(node(i+2))-x(node(1))
      qy = y(node(i+2))-y(node(1))
      qz = z(node(i+2))-z(node(1))

      call triangular_face_area_components_polymesh( px,py,pz, qx,qy,qz, nx,ny,nz )

      !
      ! > Cell-face area vector components (Area vector lies in direction of face normal)
      ! 

      arx(iface) = arx(iface) + half*nx
      ary(iface) = ary(iface) + half*ny
      arz(iface) = arz(iface) + half*nz
 
      !
      ! > Cell-face centroid components - accumulation stage
      !
      
      cx = one_third*( x(node(i+2)) + x(node(i+1)) + x(node(1)) )
      cy = one_third*( y(node(i+2)) + y(node(i+1)) + y(node(1)) )
      cz = one_third*( z(node(i+2)) + z(node(i+1)) + z(node(1)) )

      xf(iface) = xf(iface) + nx*cx
      yf(iface) = yf(iface) + ny*cy
      zf(iface) = zf(iface) + nz*cz

      ax = ax + nx
      ay = ay + ny
      az = az + nz

      !
      ! > Compute cell volumes 
      !

      vol(inp) = vol(inp) + cell_volume_part_polymesh( cx, cy, cz, nx, ny, nz ) 
      if ( iface <= numInnerFaces ) then 
      inn = neighbour(iface)
      vol(inn) = vol(inn) + cell_volume_part_polymesh( cx, cy, cz, -nx, -ny, -nz )
      endif

    enddo

    if(iface.le.numInnerFaces) then
    ! > Cell-face centroid components - final
        xf(iface) = xf(iface) / (ax+1e-30)
        yf(iface) = yf(iface) / (ay+1e-30)
        zf(iface) = zf(iface) / (az+1e-30)
    else
        xf(iface) = x(node(1))+x(node(2))+x(node(3))
        yf(iface) = y(node(1))+y(node(2))+y(node(3))
        zf(iface) = z(node(1))+z(node(2))+z(node(3))
        if(nnodes.gt.3) then
          xf(iface) = xf(iface)+x(node(4))
          yf(iface) = yf(iface)+y(node(4))
          zf(iface) = zf(iface)+z(node(4))
        endif 
        xf(iface) = xf(iface) / dble(nnodes)
        yf(iface) = yf(iface) / dble(nnodes)
        zf(iface) = zf(iface) / dble(nnodes)
        ! print*,iface,xf(iface),yf(iface),zf(iface)
    endif

  enddo



  ! Rewind 'faces' file for one more sweep
  rewind( faces_file )
  if (.not.native_mesh_files) then
    do i=1,18
      read(faces_file,*) ch
    end do
  endif

  !
  ! > Cell centers
  !

  do iface=1,numFaces

    inp = owner(iface)

    node(:) = 0

    ! Read line in 'faces' file
    if (native_mesh_files) then
      read( faces_file, * ) nnodes, (node(k), k=1,nnodes)
    else ! OpenFOAM polyMesh
      call read_line_faces_file_polyMesh(faces_file,nnodes,node,nomax)
    endif

    do i=1,nnodes-2 
      ! Vectors to vertices
      ! 2-1
      px = x(node(i+1))-x(node(1))
      py = y(node(i+1))-y(node(1))
      pz = z(node(i+1))-z(node(1))
      ! 3-1
      qx = x(node(i+2))-x(node(1))
      qy = y(node(i+2))-y(node(1))
      qz = z(node(i+2))-z(node(1))
   
      call triangular_face_area_components_polymesh( px,py,pz, qx,qy,qz, nx,ny,nz )

      xc(inp) = xc(inp) + centroid_component_part_polymesh( x(node(1)),x(node(i+1)),x(node(i+2)), nx, vol(inp) )
      yc(inp) = yc(inp) + centroid_component_part_polymesh( y(node(1)),y(node(i+1)),y(node(i+2)), ny, vol(inp) )
      zc(inp) = zc(inp) + centroid_component_part_polymesh( z(node(1)),z(node(i+1)),z(node(i+2)), nz, vol(inp) )

      if ( iface <= numInnerFaces ) then
      inn = neighbour(iface)
      xc(inn) = xc(inn) + centroid_component_part_polymesh( x(node(1)),x(node(i+2)),x(node(i+1)), -nx, vol(inn) )
      yc(inn) = yc(inn) + centroid_component_part_polymesh( y(node(1)),y(node(i+2)),y(node(i+1)), -ny, vol(inn) )
      zc(inn) = zc(inn) + centroid_component_part_polymesh( z(node(1)),z(node(i+2)),z(node(i+1)), -nz, vol(inn) )
      endif

    enddo

  enddo




  ! Rewind 'faces' file for one more sweep
  rewind( faces_file )
  if (.not.native_mesh_files) then
    do i=1,18
      read(faces_file,*) ch
    end do
  endif

  !
  ! > Interpolation factor
  !

  do iface=1,numInnerFaces

    inp = owner(iface)
    inn = neighbour(iface)

    node(:) = 0

    ! Read line in 'faces' file
    if (native_mesh_files) then
      read( faces_file, * ) nnodes, (node(k), k=1,nnodes)
    else ! OpenFOAM polyMesh
      call read_line_faces_file_polyMesh(faces_file,nnodes,node,nomax)
    endif

    xpn = xc(inn)-xc(inp)
    ypn = yc(inn)-yc(inp)
    zpn = zc(inn)-zc(inp)

    dpn = sqrt( xpn**2 + ypn**2 + zpn**2 )

    ! > > Intersection point j' of line connecting centers with cell face, we are taking only three points assuming that other are co-planar
    call find_intersection_point( &
                                 ! plane defined by three face vertices:
                                 x(node(1)),y(node(1)),z(node(1)),&
                                 x(node(2)),y(node(2)),z(node(2)), &
                                 x(node(3)),y(node(3)),z(node(3)), &
                                 ! line defined by cell center and neighbour center:
                                 xc(inp),yc(inp),zc(inp), &
                                 xc(inn),yc(inn),zc(inn), &
                                 ! intersection point (output):
                                 xjp,yjp,zjp &
                                )
    xpn = xjp - xc(inp)
    ypn = yjp - yc(inp)
    zpn = zjp - zc(inp)

    djn = sqrt( xpn**2 + ypn**2 + zpn**2 )

    ! Interpolation factor |P Pj'|/|P Pj| where P is cell center, Pj neighbour cell center and j' intersection point.
    facint(iface) = djn/dpn
    
  enddo


!
! > Report on geometrical quantities
!

  write ( *, '(a)' ) ' '
  write ( *, '(a)' ) '  Cell data: '

  call r8vec_print_some ( numCells, vol, 1, 10, &
      '  First 10 elements of cell volumes array:' )

  call r8vec_print_some ( numCells, xc, 1, 10, &
      '  First 10 elements of cell x-centers array:' )

  call r8vec_print_some ( numCells, yc, 1, 10, &
      '  First 10 elements of cell y-centers array:' )

  call r8vec_print_some ( numCells, zc, 1, 10, &
      '  First 10 elements of cell z-centers array:' )

  write ( *, '(a)' ) ' '
  write ( *, '(a)' ) '  Face data: '

  call i4vec_print2 ( 10, owner, neighbour, '  First 10 lines of owner and neighbour arrays:' )

  call r8vec_print_some ( numFaces, arx, 1, 10, &
      '  First 10 elements of Arx array:' )

  call r8vec_print_some ( numFaces, ary, 1, 10, &
      '  First 10 elements of Ary array:' )

  call r8vec_print_some ( numFaces, arz, 1, 10, &
      '  First 10 elements of Arz array:' )

    call r8vec_print_some ( numFaces, xf, 1, 10, &
      '  First 10 elements of xf array:' )

  call r8vec_print_some ( numFaces, yf, 1, 10, &
      '  First 10 elements of yf array:' )

  call r8vec_print_some ( numFaces, zf, 1, 10, &
      '  First 10 elements of zf array:' )

  call r8vec_print_some ( numInnerFaces, facint, 1, 10, &
      '  First 10 elements of interpolation factor (facint) array:' )


!
!  > CLOSE polyMesh format file: 'points', 'faces', 'owner', 'neighbour', 'boundary'.
!
  close ( points_file )
  close ( faces_file )
  close ( owner_file )
  close ( neighbour_file)
  close ( boundary_file)
!+-----------------------------------------------------------------------------+

end subroutine mesh_geometry


end module
