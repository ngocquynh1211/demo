#!/usr/bin/env python
import sys
from cx_Freeze import setup, Executable

excludes = [
   "MacOS", "macpath", "os2", "os2emxpath", "ntpath",
   "email", "gopherlib", "ftplib", "mimetypes", "nturl2path", "macurl2path",
   "distutils", "doctest", "pdb", "pydoc",
   "gettext", "uu", "quopri",
   "xml.sax.expatreader",
   "getopt", "popen2",
   "pyVmomi.CimsfccTypes",
   "pyVmomi.DmsTypes",
   "pyVmomi.HbrReplicaTypes",
   "pyVmomi.HmoTypes",
   "pyVmomi.ImgFactTypes",
   "pyVmomi.OmsTypes",
   "pyVmomi.RbdTypes",
   "pyVmomi.VorbTypes",
]

includes = [
   "encodings.ascii", "encodings.utf_8",
   "encodings.gbk", "encodings.gb18030",
   "encodings.cp950", "encodings.big5", "encodings.big5hkscs",
   "encodings.euc_jp", "encodings.shift_jis", "encodings.iso2022_jp",
   "encodings.cp949", "encodings.cp1252", "encodings.euc_kr",
   "encodings.iso8859_1", "encodings.iso8859_2", "encodings.iso8859_5",
   "encodings.iso8859_8", "encodings.iso8859_10",
   "encodings.iso8859_15", "encodings.iso8859_16",
   "uuid", "lxml", "lxml.etree",  'lxml._elementpath',  "gzip", "pyVim", "pyVmomi"]
packages = ["lxml", "OpenSSL", "inspect"]
buildOptions = dict(
   compressed = True,
   optimize = 2,
   excludes = excludes,
   includes = includes,
   include_in_shared_zip = True,
   create_shared_zip = True,
   packages = packages,
   path =  ["/build/toolchain/lin64/lxml-3.3.1/lib/python2.7/site-packages/", "/build/toolchain/lin64/pyopenssl-0.13-5/lib/python2.7/site-packages/"] + sys.path)
setup(name = "sso_python_util",
      description = "ESX command line configuration",
      options = dict(build_exe = buildOptions),
      executables = [Executable("ssoclient.py")])
