#! /usr/bin/env python3
# Last Modification: $Id$
#=======================================================================
# write.py
#
# Facilities for writing the Pencil Code data in VTK.
#
# Chao-Chin Yang, 2017-08-24
#=======================================================================
def var(**kwarg):
    """Writes one VAR data file in VTK format under allprocs/.

    Keyword Arguments
        **kwarg
            Keywords passed to module read.
    """
    # Author: Chao-Chin Yang
    # Created: 2017-08-24
    # Last Modified: 2017-08-24
    from . import read
    from evtk.hl import gridToVTK
    from Toolbox import get

    # Read the parameters.
    datadir = kwarg.pop("datadir", "./data")
    par = kwarg.pop("par", None)
    if par is None: par = read.parameters(datadir=datadir)

    # Currently only works for rectilinear grid.
    if par.coord_system != "cartesian":
        raise NotImplementedError("Non-rectilinear grid")

    # Read the grid.
    grid_kw = get.pairs(kwarg, "trim")
    g = read.grid(datadir=datadir, par=par, **grid_kw)

    # Read the variable names.
    varnames = read.varname(datadir=datadir)

    # Read the VAR file.
    f = read.var(datadir=datadir, par=par, **kwarg)

    # Organize the data.
    pointData = {}
    for var in varnames:
        pointData[var] = getattr(f, var)

    # Get the file name of the snapshot.
    if "ivar" in kwarg:
        varfile = "VAR{}".format(kwarg["ivar"])
    elif "varfile" in kwarg:
        varfile = kwarg["varfile"]
    else:
        varfile = "var"

    # Write the data.
    print("Writing", varfile, "in VTK under allprocs/...")
    path = datadir + "/allprocs/" + varfile
    gridToVTK(path, g.x, g.y, g.z, pointData=pointData)
    print("Done. ")
