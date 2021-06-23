%{!?_name: %global _name mpich-ofi-default}
%{!?_version: %global _version unknown_version}
%{!?_release: %global _release unknown_release}

Name:           %{_name}
Version:        %{_version}
Release:        %{_release}
Summary:        MPICH-OFI internal development build
License:        BSD
Group:          Development/Libraries/Parallel
Source:         %{name}.tar.bz2
Url:            https://github.intel.com/csr/mpich-ofi
BuildRoot:      %{_tmppath}/%{name}-build
Prefix:         /usr/mpi
AutoReqProv:    yes

# Don't include xpmem in the requirements because this package is usually installed manually, not by RPM
%global __requires_exclude ^(libxpmem|libze_loader)[.]so.*$

%define _unpackaged_files_terminate_build 0
%define debug_package %{nil}

%description
Custom build of MPICH-OFI

%prep
%setup -q -n %{name}

%build

%install
LANG=C

if [ x"$RPM_INSTALL_PREFIX" = x"" ]; then
    # It seems it is broken RPM ignoring --prefix option, so let's use default prefix.
    export RPM_INSTALL_PREFIX="/usr/mpi"
fi

cp -a * %{buildroot}
rm %{buildroot}/$RPM_INSTALL_PREFIX/%{name}/lib/libmpi.la
rm %{buildroot}/$RPM_INSTALL_PREFIX/%{name}/lib/libmpicxx.la
rm %{buildroot}/$RPM_INSTALL_PREFIX/%{name}/lib/libmpifort.la

find %{buildroot} -not -type d > files
sed -i -- 's/.*\/usr/\/usr/' files
sed -i -- 's/.*\.la//' files

#This change is necessary for RPMs to work in Dudley
sed -i 's:#! /bin/perl:#! /usr/bin/perl:' %{buildroot}/"$RPM_INSTALL_PREFIX/%{name}/bin/parkill"

%clean
if [ x"$RPM_INSTALL_PREFIX" = x"" ]; then
    # It seems it is broken RPM ignoring --prefix option, so let's use default prefix.
    export RPM_INSTALL_PREFIX="/usr/mpi"
fi

rm -rf %{buildroot}

%pre
LANG=C

if [ x"$RPM_INSTALL_PREFIX" = x"" ]; then
    # It seems it is broken RPM ignoring --prefix option, so let's use default prefix.
    export RPM_INSTALL_PREFIX="/usr/mpi"
fi

rm -rf $RPM_INSTALL_PREFIX/%{name}

%post
LANG=C

if [ x"$RPM_INSTALL_PREFIX" = x"" ]; then
    # It seems it is broken RPM ignoring --prefix option, so let's use default prefix.
    export RPM_INSTALL_PREFIX="/usr/mpi"
fi

patch_file()
{
    file_to_patch="${4}/${1}"
    template="$2"
    var="$3"
    if [ -f "$file_to_patch" -a ! -h "$file_to_patch" -a -w "$file_to_patch" ]; then
        cp "$file_to_patch" "$file_to_patch.old~"
        cat "$file_to_patch.old~" | sed s@$template@$var@g > "$file_to_patch.new~"
        cp "$file_to_patch.new~" "$file_to_patch"
        rm -f "$file_to_patch.new~" "$file_to_patch.old~"
    fi
}

FILES_TO_PATCH="mpif77 mpif90 mpic++ mpicc mpicxx mpifort openpa.pc mpich.pc"

for file in $FILES_TO_PATCH ; do
    patch_file "$file" "/tmp/%{name}/usr/mpi" "$RPM_INSTALL_PREFIX" "$RPM_INSTALL_PREFIX/%{name}/bin"
    patch_file "$file" "/tmp/%{name}/usr/mpi" "$RPM_INSTALL_PREFIX" "$RPM_INSTALL_PREFIX/%{name}/lib/pkgconfig"
done

flavor_string=""
if [ "%{_flavor}" != "regular" ]; then
    flavor_string="-%{_flavor}"
fi

EXTENSIONS="tcl lua"
for extension in $EXTENSIONS ; do
    if [ "%{_configs}" = "debug" ]; then
        patch_file "%{version}.%{release}.${extension}" "/usr/mpi" "$RPM_INSTALL_PREFIX" \
            "$RPM_INSTALL_PREFIX/modulefiles/mpich/%{_compiler}-%{_provider}-debug${flavor_string}/"

        patch_file "%{version}.%{release}.${extension}" "/usr/mpi" "$RPM_INSTALL_PREFIX" \
            "$RPM_INSTALL_PREFIX/modulefiles/mpich/%{_compiler}-%{_provider}-deterministic${flavor_string}/"
    else
        patch_file "%{version}.%{release}.${extension}" "/usr/mpi" "$RPM_INSTALL_PREFIX" \
            "$RPM_INSTALL_PREFIX/modulefiles/mpich/%{_compiler}-%{_provider}${flavor_string}/"
    fi
done

#Create the file in /etc/profile.d to update the module path
echo "#!/bin/bash" > /etc/profile.d/mpich-%{_compiler}.sh
echo "export MODULEPATH=$RPM_INSTALL_PREFIX/modulefiles:\$MODULEPATH" >> /etc/profile.d/mpich-%{_compiler}.sh

echo "#!/bin/bash" > /etc/profile.d/mpich-%{_compiler}.csh
echo "setenv MODULEPATH $RPM_INSTALL_PREFIX/modulefiles:\$MODULEPATH" >> /etc/profile.d/mpich-%{_compiler}.csh

/sbin/ldconfig

exit 0

%preun -p /sbin/ldconfig

%postun -p /sbin/ldconfig

%files -f files

%changelog

