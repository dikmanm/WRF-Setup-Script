#!/bin/bash
. variables
fet=$force_extract_tars #for convenience
[ $use_ld ] && ld_flag="--with-gnu-ld" || ld_flag=""

#In order to run the WRF and WPS configure and compile scripts as the user that called this script
#(so that the files can be edited without sudo) when this script is called, we have to use sudo to
#specifically switch back to that user for the duration of the command.
#If we aren't running as sudo, then we don't need this command, so it is set to ""
[ $SUDO_USER ] && unsudo="sudo -u $SUDO_USER" || unsudo=""

if ( ! $keep_namelists ); then
	read -p "keep_namelists in 'variables' is currently set to false. If you proceed, you will loose any existing namelist files. Is this okay? [y/N] " yn
	declare -l yn
	if [ "$yn" != "y" ]; then
		keep_namelists=true
		echo "Changed keep_namelists to true for this run. Please change the value in 'variables' if you wish to avoid this prompt."
	else
		read -p "Leaving keep_namelists false. Some existing namelists may be deleted. Press [Enter] to continue."
	fi
fi

set -e
set -o nounset

#The [ ! -d "<path>" ] && <action> form only performs <action> if <path> does not exist or is not a directory
$fet || [ ! -d "$hydra_path" ]		&& $unsudo tar zxvf hydra-$hydra_version.tar.gz || echo "Already extracted Hydra"
$fet || [ ! -d "$mpich_path" ]		&& $unsudo tar zxvf mpich-$mpich_version.tar.gz || echo "Already extracted MPICH"
$fet || [ ! -d "$hdf5_path" ]		&& $unsudo tar zxvf hdf5-$hdf5_version.tar.gz || echo "Already extracted HDF5"
$fet || [ ! -d "$netcdf_path" ]		&& $unsudo tar zxvf netcdf-$netcdf_version.tar.gz || echo "Already extracted NetCDF"
$fet || [ ! -d "$netcdf_fortran_path" ] && $unsudo tar zxvf netcdf-fortran-$netcdf_fortran_version.tar.gz || echo "Already extracted NetCDF Fortran"
$fet || [ ! -d "$WRF_path" ]		&& $unsudo tar zxvf WRFV$wrf_version.tar.gz || echo "Already extracted WRF"
$fet || [ ! -d "$WRF_Chem_path" ]	&& $unsudo tar zxvf WRFV$wrf_major_version-Chem-$wrf_version.tar.gz -C $WRF_path || echo "Already extracted WRF-Chem"
$fet || [ ! -d "$WPS_path" ]		&& $unsudo tar zxvf WPSV$wrf_version.tar.gz || echo "Already extracted WPS"

if (! $skip_mpich ); then
	if (! $lazy_recompile) || [ ! -d "$hydra_prefix" ]; then
		cd $hydra_path
		$unsudo ./configure --prefix=$hydra_prefix $ld_flag 2>&1 | $unsudo tee ./configure.log
		make && make check install 2>&1 | $unsudo tee ./make.log
		cd ../
	else
		echo "Skipping compiling Hydra"
	fi

	if (! $lazy_recompile) || [ ! -d "$mpich_prefix" ]; then
		cd $mpich_path
		$unsudo ./configure --prefix=$mpich_prefix $ld_flag --with-pm=hydra 2>&1 | $unsudo tee ./configure.log
		make && make check install 2>&1 | $unsudo tee ./make.log
		cd ../
	else
		echo "Skipping compiling MPICH"
	fi
fi

while [ "$(which mpicc)" == "" -o "$(which mpiexec)" == "" -o "$(which mpif90)" == "" ]; do
	echo "Some of the required MPICH executables cannot be found on your PATH."
	echo "This can be fixed by adding the following links:"
	[ "$(which mpicc)" == "" ] && echo "/usr/bin/mpicc -> $mpich_prefix/bin/mpicc"
	[ "$(which mpiexec)" == "" ] && echo "/usr/bin/mpiexec -> $mpich_prefix/bin/mpiexec"
	[ "$(which mpif90)" == "" ] && echo "/usr/bin/mpif90 -> $mpich_prefix/bin/mpif90"
	read -p "Would you like me to add these links? [y/N] " yn
	declare -l yn
	if [ $yn == "y" ]; then
		[ "$(which mpicc)" == "" ] && ln -s $mpich_prefix"/bin/mpicc" "/usr/bin/mpicc"
		[ "$(which mpiexec)" == "" ] && ln -s $mpich_prefix"/bin/mpiexec" "/usr/bin/mpiexec"
		[ "$(which mpif90)" == "" ] && ln -s $mpich_prefix"/bin/mpif90" "/usr/bin/mpif90"
	else
		read -p "Please set your path.  Press [Enter] when you have done so."
	fi
done

if (! $lazy_recompile) || [ ! -d "$hdf5_prefix" ]; then
	cd $hdf5_path
	$unsudo $compilers ./configure --enable-parallel --enable-debug=all --enable-codestack $ld_flag --prefix=$hdf5_prefix 2>&1 | $unsudo tee ./configure.log
	$unsudo $compilers make && $unsudo $compilers make check && $compilers make install 2>&1 | $unsudo tee ./make.log
	if [! -e "$hdf5_prefix/lib/libhdf5.a"]; then
		echo "Failed to build HDF5.  Please check configure.log and/or make.log in $hdf5_path."
		kill -INT $$
	fi
	cd ../
else
	echo "Skipping compiling HDF5"
fi

flags="CPPFLAGS=-I$hdf5_prefix/include LDFLAGS=-L$hdf5_prefix/lib LD_LIBRARY_PATH=$hdf5_prefix/lib"
if (! $lazy_recompile) || [ ! -d "$netcdf_prefix" ]; then
	cd $netcdf_path
	$unsudo $compilers ./configure --enable-doxygen $ld_flag --prefix=$netcdf_prefix $flags 2>&1 | $unsudo tee ./configure.log
	$unsudo $compilers make check && $compilers make install 2>&1 | $unsudo tee ./make.log
	if [! -e "$netcdf_prefix/lib/libnetcdf.a"]; then
		echo "Failed to build NetCDF.  Please check configure.log and/or make.log in $netcdf_path."
		kill -INT $$
	fi
	cd ../
else
	echo "Skipping compiling NetCDF"
fi

flags="CPPFLAGS=-I$netcdf_prefix/include LDFLAGS=-L$netcdf_prefix/lib LD_LIBRARY_PATH=$netcdf_prefix/lib"
if (! $lazy_recompile) || [ ! -e "$netcdf_prefix/include/netcdf.inc" ]; then
	cd $netcdf_fortran_path
	$unsudo $compilers ./configure --enable-doxygen $ld_flag --prefix=$netcdf_prefix $flags 2>&1 | $unsudo tee ./configure.log
	$unsudo $compilers make check && $compilers make install 2>&1 | $unsudo tee ./make.log
	if [! -e "$netcdf_prefix/lib/libnetcdff.a"]; then
		echo "Failed to build NetCDF.  Please check configure.log and/or make.log in $netcdf_fortran_path."
		kill -INT $$
	fi
	cd ../
else
	echo "Skipping compiling NetCDF Fortran"
fi

cd $WRF_path
if ( $keep_namelists ) && [ -e "./run/namelist.input" ]; then
	$unsudo cp "./run/namelist.input" "namelist.input.back"
fi
$unsudo `WRFIO_NCD_LARGE_FILE_SUPPORT=1 NETCDF=$netcdf_prefix $compilers` ./configure $compilers $flags 2>&1 | $unsudo tee ./configure.log
if ( $use_wrf_regex_fixes ); then
	$unsudo perl -0777 -i -pe 's/(LIB_EXTERNAL[ \t]*=([^\\\n]*\\\n)*[^\n]*)\n/$1 -lgomp\n/is' ./configure.wrf
else
	echo "Skipping WRF regex fixes."
fi
$unsudo $compilers ./compile wrf 2>&1 | $unsudo tee ./compile_wrf.log
$unsudo $compilers ./compile
echo "Please enter the test case you would like to run (this can include the '-j n' part) or none [Default: none]:"
read test_case
declare -l test_case
if [ $(echo ${#test_case}) -gt 4 ] && [ "$test_case" != "" -a "$test_case" != "none" ]; then
    $unsudo $compilers ./compile "$test_case" 2>&1 | $unsudo tee ./compile_test_case.log
else
    echo "Skipping compiling a test case."
fi
if ( $keep_namelists ) && [ -e "namelist.input.back" ]; then
	$unsudo mv "namelist.input.back" "./run/namelist.input"
fi
cd ../

cd $WPS_path
if ( $keep_namelists ) && [ -e "./namelist.wps" ]; then
	$unsudo cp "./namelist.wps" "namelist.wps.back"
fi
$unsudo `WRFIO_NCD_LARGE_FILE_SUPPORT=1 NETCDF=$netcdf_prefix $compilers` ./configure $compilers $flags #2>&1 | $unsudo tee ./configure.log #The WPS configure does something that messes with logging, so this is disabled for now.
echo "For reasons unknown, WPS's configure sometimes adds invalid command line options to DM_FC and DM_CC and neglects to add some required links to NCARG_LIBS."
echo "However, this script fixes those problems, so... No need to worry about it."
if ( $use_wps_regex_fixes ); then
	$unsudo perl -0777 -i -pe 's/[ \t]*(-f90=($\([^\(]*\))|[^ \t\n]*)|-cc=($\([^\(]*\))|[^ \t\n]*)*)[ \t]*//igs' ./configure.wps
	$unsudo perl -0777 -i -pe 's/(NCARG_LIBS[ \t]*=([^\\\n]*\\\n)*[^\n]*)\n/$1 -lcairo -lfontconfig -lpixman-1 -lfreetype\n/is' ./configure.wps
	$unsudo perl -0777 -i -pe 's/(WRF_LIB[ \t]*=([^\\\n]*\\\n)*[^\n]*)\n/$1 -lgomp\n/is' ./configure.wps
else
	echo "Skipping WPS regex fixes."
fi
$unsudo `NETCDF=$netcdf_prefix $compilers` ./compile 2>&1 | $unsudo tee ./compile.log
$unsudo `NETCDF=$netcdf_prefix $compilers` ./compile plotgrids 2>&1 | $unsudo tee ./compile_plotgrids.log
if ( $keep_namelists ) && [ -e "namelist.wps.back" ]; then
	$unsudo mv "namelist.wps.back" "./namelist.wps"
fi
cd ../

echo "Please confirm that all of the executables have been appropriately created in the WRFV$wrf_major_version and WPSV$wrf_major_version directories."
echo "You will still need to extract your Geogrid data and get GFS data relevant to the times you are interested in simulating."
