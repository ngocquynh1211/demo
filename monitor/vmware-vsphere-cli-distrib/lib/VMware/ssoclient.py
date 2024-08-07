#!/usr/bin/python

"""
Simple command-line program for demostrating SSO implementation in Python.
"""

from pyVim.connect import Connect, vim
from pyVim.connect import VimSessionOrientedStub
from pyVmomi import cis
from pyVmomi.SoapAdapter import SoapStubAdapter, SessionOrientedStub
from optparse import OptionParser
from lxml import etree
from OpenSSL import crypto
import time
import re
import base64
import hashlib

from uuid import uuid4
from StringIO import StringIO
from urlparse import urlparse
import sso
import ssl
CIS_VMODL_VERSION = 'cis.cm.version.version1'
CM_MOID = 'ServiceManager'
SSO_PRODUCT_ID = 'com.vmware.cis'
SSO_TYPE_ID = 'cs.identity'
EP_SSO_PROTOCOL = 'wsTrust'
EP_SSO_TYPE_ID = 'com.vmware.cis.cs.identity.sso'

VC_PRODUCT_ID = 'com.vmware.cis'
VC_TYPE_ID = 'vcenterserver'
EP_VC_PROTOCOL = 'vmomi'
EP_VC_TYPE_ID = 'com.vmware.vim'

def GetOptions():
   """
   Supports the command-line arguments listed below.
   """

   parser = OptionParser()
   parser.add_option("--server",
                     default=None,
                     help="remote host to connect to")
   parser.add_option("--stsurl",
                     default=None,
                     help="STS server URL")
   parser.add_option("--cmurl",
                     default=None,
                     help="CM URL")
   parser.add_option("-u", "--user",
                     default=None,
                     help="User name to use when connecting to hostd")
   parser.add_option("-p", "--password", "--pwd",
                     default=None,
                     help="Password to use when connecting to hostd")
   parser.add_option("--savesamltoken",
                     default=None,
                     help="File to save SAML token")
   parser.add_option("--samltoken",
                     default=None,
                     help="SAML token file to login")
   parser.add_option("--public_key",
                     default=None,
                     help="public key file")
   parser.add_option("--sts_cert",
                     default=None,
                     help="sts_cert file")
   parser.add_option("--private_key",
                     default=None,
                     help="private key file")
   (options, _) = parser.parse_args()
   return options

def _getBearerSamlAssertion(options):
   """
   Gets the Bearer SAML token from SSO server
   """

   import sso
   #cert = soapStub.schemeArgs['cert_file']
   #key = soapStub.schemeArgs['key_file']

   #print "Getting bearer token"
   try:
      authenticator = sso.SsoAuthenticator(options.stsurl,
                                           None)
      context = None
      if hasattr(ssl, '_create_unverified_context'):
          context = ssl._create_unverified_context()
      samlAssertion = authenticator.get_bearer_saml_assertion(
                         options.user,
                         base64.b64decode(options.password),
                         None, None, 600, 1200, True, ssl_context=context)
   except Exception, err:
      message = "Could not get the token from STS server '" + options.stsurl + "'"
      print message + "\n"
      raise BaseException(err)

   if options.savesamltoken:
      #print "Saving saml token"
      file = open(options.savesamltoken, 'w')
      file.write(samlAssertion)
      file.close()

   return samlAssertion

def _getHokSamlAssertion(options):
        au = sso.SsoAuthenticator(options.stsurl, options.sts_cert)
        hok_token = get_hok_saml_assertion_with_username_password(au, options.user,
                                                                     base64.b64decode(options.password),
                                                                     options.public_key,
                                                                     options.private_key,
                                                                     request_duration = 3600)
        return hok_token
 
def _getHokSamlAssertion_old(options):
   """
   Gets the HOK SAML token from SSO server
   """

   token = _getBearerSamlAssertion(options)
   authenticator = sso.SsoAuthenticator(options.stsurl)
   samlAssertion = authenticator.get_hok_saml_assertion(public_key=options.public_key,
                                                        private_key=options.private_key,
                                                        delegatable=True,
                                                        request_duration=3600,
                                                        act_as_token=token)
   if options.savesamltoken:
      #print "Saving saml token"
      file = open(options.savesamltoken, 'w')
      file.write(samlAssertion)
      file.close()

   return samlAssertion

def _extractCookie(token, options):
   """
   Extract the session cookie after doing loginbytoken
   """
   server = options.server
   portNo = 443
   pathStr = "/sdk"
   if options.server == None:
      vcUrl =  _getVCUrlFromCM(options.cmurl, token)
      server, portNo, protocol, pathStr =  _parseURL(vcUrl)

   try:
      context = None
      if hasattr(ssl, '_create_unverified_context'):
         context = ssl._create_unverified_context()
      # Get soap stub
      soapStub = SoapStubAdapter(host=server,
                                 port=portNo,
                                 version="vim.version.version9",
                                 path=pathStr,
                                 certKeyFile=options.private_key,
                                 certFile=options.sts_cert,
                                 sslContext=context
                                 )
      soapStub.samlToken = token
      si = vim.ServiceInstance("ServiceInstance", soapStub)
      sm = si.content.sessionManager
      sm.LoginByToken()
   except Exception, err:
      #message =  "Could not get the SAML token for server '" + \
      #           server + "'" + \
      #           " from STS server '" + options.stsurl + "'"
      #print message + "\n"
      raise BaseException(err)

   return soapStub.cookie

def _getStsUrl(cmUrl):
   userSession = None

   if not cmUrl:
      message = "Must specify a CM url"
      raise SessionArgumentException(message)

   cmStub = SoapStubAdapter(url=cmUrl, version=CIS_VMODL_VERSION)
   cmsm = cis.cm.ServiceManager(CM_MOID, cmStub)

   sc = cis.cm.searchCriteria()
   sc.serviceType = cis.cm.serviceType()
   sc.serviceType.productId = SSO_PRODUCT_ID
   sc.serviceType.typeId = SSO_TYPE_ID
   sc.folder = cis.cm.site.Folder()
   sc.folder.parentId = ""
   try:
      sis = cmsm.Search(sc)
   except Exception, err:
      message = "Could not search STS url from CM '" + cmUrl + "'"
      print message + "\n"
      raise BaseException(err)

   stsUrl = None

   for si in sis:
      for ep in si.serviceEndPoints:
         if ep.endPointType.endPointProtocol == EP_SSO_PROTOCOL or ep.endPointType.typeId == EP_SSO_TYPE_ID:
            stsUrl = str(ep.url)
            break
   return stsUrl

def _parseURL(url):
   if url:
      import urlparse
      url = urlparse.urlparse(url)
      protocol = url.scheme
      host = url.hostname
      if url.port:
         try:
            port = int(url.port)
         except ValueError:
            message = "Invalid port number %s in URL" % url.port
            raise SessionArgumentException(message)
      else:
         port = (protocol == "http") and 80 or 443
      path = url.path
      return host, port, protocol, path

def _getVCUrlFromCM(cmUrl, samlToken):
   if not cmUrl:
      message = "Must specify a CM url"
      raise SessionArgumentException(message)
   cmStub = SoapStubAdapter(url=cmUrl, version=CIS_VMODL_VERSION)
   cmStub.samlToken = samlToken
   cmsm = cis.cm.ServiceManager(CM_MOID, cmStub)
   cmsm.LoginByToken()

   sc = cis.cm.searchCriteria()
   sc.serviceType = cis.cm.serviceType()
   sc.serviceType.productId = VC_PRODUCT_ID
   sc.serviceType.typeId = VC_TYPE_ID
   sc.folder = cis.cm.site.Folder()
   sc.folder.parentId = ''
   try:
      sis = cmsm.Search(sc)
   except Exception, err:
      message = "Invalid CM url"
      raise SessionArgumentException(message)
   vcUrl = None
   for si in sis:
      for ep in si.serviceEndPoints:
         if ep.endPointType.endPointProtocol == EP_VC_PROTOCOL or ep.endPointType.typeId == EP_VC_TYPE_ID:
            vcUrl = str(ep.url)
            break
   return vcUrl

def _extract_certificate(cert):
    '''
    Extract DER certificate/private key from DER/base64-ed DER/PEM string.

    @type           cert: C{str}
    @param          cert: Certificate/private key in one of three supported formats.

    @rtype: C{str}
    @return: Certificate/private key in DER (binary ASN.1) format.
    '''
    if not cert:
        raise IOError('Empty certificate')
    signature = cert[0]
    # DER certificate is sequence.  ASN.1 sequence is 0x30.
    if signature == '\x30':
        return cert
    # PEM without preamble.  Base64-encoded 0x30 is 0x4D.
    if signature == '\x4D':
        return base64.b64decode(cert)
    # PEM with preamble.  Starts with '-'.
    if signature == '-':
        return base64.b64decode(re.sub('-----[A-Z ]*-----', '', cert))
    # Unknown format.
    raise IOError('Invalid certificate file format')

def get_hok_saml_assertion_with_username_password(ssoAuth,
                                                   username,
                                                   password,
                                                   public_key,
                                                   private_key,
                                                   request_duration=60,
                                                   token_duration=600,
                                                   act_as_token=None,
                                                   delegatable=True):
     '''
     Extracts the assertion from the response received from the Security
     Token Service.

     @type          username: C{str}
     @param         username: Username for the user for which holder of key token
                              needs to be requested.
     @type          password: C{str}
     @param         password: Password for the user for which holder of key token
                              needs to be requested.
     @type        public_key: C{str}
     @param       public_key: File containing the public key for the
                              user in PEM format.
     @type       private_key: C{str}
     @param      private_key: File containing the private key for the
                              user in PEM format.
     @type  request_duration: C{long}
     @param request_duration: The duration for which the request is valid. If
                              the STS receives this request after this
                              duration, it is assumed to have expired. The
                              duration is in seconds and the default is 60s.
     @type    token_duration: C{long}
     @param   token_duration: The duration for which the SAML token is issued
                              for. The duration is specified in seconds and
                              the default is 600s.
     @type      act_as_token: C{str}
     @param     act_as_token: Bearer/Hok token which is delegatable
     @type       delegatable: C{boolean}
     @param      delegatable: Whether the generated token is delegatable or not
     @rtype: C{str}
     @return: The SAML assertion.
     '''
     request = sso.SecurityTokenRequest(username=username,
                                    password=password,
                                    public_key=public_key,
                                    private_key=private_key,
                                    request_duration=request_duration,
                                    token_duration=token_duration)
     soap_message = construct_hok_request_with_username_password(request,
                                                                 delegatable=delegatable,
                                                                 act_as_token=act_as_token)
     hok_token = ssoAuth.perform_request(soap_message,
                                      public_key,
                                      private_key)
     return etree.tostring(
                 sso._extract_element(etree.fromstring(hok_token),
                     'Assertion',
                     {'saml2': "urn:oasis:names:tc:SAML:2.0:assertion"}),
                     pretty_print=False)

def construct_hok_request_with_username_password(secTokenReq, delegatable=True, act_as_token=None):
     '''
     Constructs the actual HoK token SOAP request.

     @type   delegatable: C{boolean}
     @param  delegatable: Whether the generated token is delegatable or not
     @type  act_as_token: C{str}
     @param act_as_token: Bearer/Hok token which is delegatable
     @rtype: C{str}
     @return: HoK token SOAP request.
     '''
     secTokenReq._binary_security_token = base64.b64encode(_extract_certificate(secTokenReq._public_key)) 
     secTokenReq._use_key = sso.USE_KEY_TEMPLATE % secTokenReq.__dict__
     secTokenReq._security_token = (sso.USERNAME_TOKEN_TEMPLATE + sso.BINARY_SECURITY_TOKEN_TEMPLATE) % secTokenReq.__dict__
     secTokenReq._key_type = "http://docs.oasis-open.org/ws-sx/ws-trust/200512/PublicKey"
     secTokenReq._delegatable = str(delegatable).lower()
     secTokenReq._act_as_token = act_as_token
     if act_as_token is None:
         secTokenReq._xml_text = sso._canonicalize(sso.REQUEST_TEMPLATE % secTokenReq.__dict__)
     else:
         secTokenReq._xml_text = sso.ACTAS_REQUEST_TEMPLATE % secTokenReq.__dict__
     secTokenReq.sign_request()
     return etree.tostring(secTokenReq._xml, encoding='utf-8', pretty_print=False)

def main():
   """
   Simple command-line program for demostrating SSO implementation in Python.
   """

   options = GetOptions()
   token = None

   if options.cmurl:
      options.stsurl = _getStsUrl(options.cmurl)

   if options.stsurl == None:
      raise BaseException ("STS url is not specified")

   if options.samltoken:
      file = open(options.samltoken, 'r')
      token = file.read()
      file.close()
   if options.private_key == None:
      token = _getBearerSamlAssertion(options)
   
   else:
      token = _getHokSamlAssertion(options)
   
   if options.server == None:
      print token
   else:
      cookie = _extractCookie(token, options)
      print cookie
   return 0

# Start program
if __name__ == "__main__":
   main()
