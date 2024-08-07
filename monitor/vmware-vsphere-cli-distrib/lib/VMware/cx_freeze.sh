#!/bin/sh
VIPERL_SRC=.
if  [ ! -z "$1" ] ; then
 VIPERL_SRC=$1/lib/VMware
fi

echo "viperl src dir:" ${VIPERL_SRC}

PYVMOMIPATH=
PYVMOMIPATH=${VIPERL_SRC}/pySdk-fling
echo "Using pyVmomi in ${PYVMOMIPATH}"

tar -xvzf ${VIPERL_SRC}/vSphere-python-api*.tar.gz -C ${VIPERL_SRC}
unzip -o ${VIPERL_SRC}/pyvmomi.zip -d ${PYVMOMIPATH}

# Setup build path in tmp (to avoid my own name shows up in executable)
buildPath=/tmp/viperl
rm -rf ${buildPath}
mkdir -p ${buildPath}/pyVmomi
mkdir -p ${buildPath}/pyVim
cp -rf ${PYVMOMIPATH}/pyVmomi ${VIPERL_SRC}/
cp -rf ${PYVMOMIPATH}/pyVim ${VIPERL_SRC}/
cp -rf ${PYVMOMIPATH}/pyVmomi ${buildPath}/
cp -rf ${PYVMOMIPATH}/pyVim ${buildPath}/
cp -f ${VIPERL_SRC}/*.py ${buildPath}

# Build executable
pushd ${buildPath}
pythonRoot=/build/toolchain/lin64/python-2.7.12-openssl1.0.2j
export PYTHONPATH="${PYTHONPATH}:/build/toolchain/lin64/cx-Freeze-4.3.4-python2.7.12-openssl1.0.2j/lib/python2.7/site-packages/:/build/toolchain/lin64/pyopenssl-0.13-5/lib/python2.7/site-packages"
${pythonRoot}/bin/python ${VIPERL_SRC}/cx_freeze_setup.py build_exe -b "pyexe" -i ${VIPERL_SRC}/cx_freeze_console.py
/usr/bin/env cp -f ${pythonRoot}/lib/libpython2.7.so.1.0 pyexe/
/usr/bin/env cp -r ./pyexe ${VIPERL_SRC}/
#files=`ls -lR`
#echo ${files}
popd

#pushd ${VIPERL_SRC}
#files=`ls -l`
#echo ${files}
#popd
