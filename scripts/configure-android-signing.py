#!/usr/bin/env python3
"""One-time setup using the operator's own GitHub login. Never prints private key/passwords."""
import argparse
import base64
import getpass
import hashlib
import os
from pathlib import Path
import re
import shutil
import ssl
import subprocess
import sys

REPO = 'novinkikinoruss-rgb/-'

def run(args, payload=None, env=None):
    result = subprocess.run(args, input=payload, capture_output=True, env=env)
    if result.returncode:
        # Don't echo command bodies, keytool output or an arbitrary process environment.
        if b'403' in result.stderr or b'Resource not accessible' in result.stderr:
            raise RuntimeError('GitHub denied Secrets access (403). Authorise a token with Secrets: Read and write for '+REPO+'.')
        raise RuntimeError(args[0]+' failed; no private values were printed. Check login, key/password and repository access.')
    return result.stdout

def setup(args):
    for binary in ['gh', 'keytool']:
        if not shutil.which(binary):
            raise RuntimeError('Install '+binary+' before running setup.')
    # Check permission BEFORE creating any key. A denied integration cannot change itself.
    run(['gh','api','repos/'+REPO+'/actions/secrets/public-key'])
    names = run(['gh','secret','list','--repo',REPO,'--json','name','--jq','.[].name']).decode().splitlines()
    key = Path(args.keystore).expanduser().resolve()
    repository = Path(__file__).resolve().parents[1]
    if key == repository or repository in key.parents:
        raise RuntimeError('Store the keystore outside the source checkout.')
    if args.create and ('DRIVER_ANDROID_KEYSTORE_BASE64' in names or key.exists()):
        raise RuntimeError('A signing key already exists locally or on GitHub. Reuse the original key; do not replace it.')
    if not args.create and not key.is_file():
        raise RuntimeError('Keystore missing. Use --create only for the first release.')
    password = getpass.getpass('Keystore password (at least 12 characters): ')
    if len(password)<12:
        raise RuntimeError('Use at least 12 characters.')
    key_password = password if args.create else getpass.getpass('Signing key password: ')
    env = dict(os.environ, DRIVER_SETUP_STORE_PASSWORD=password, DRIVER_SETUP_KEY_PASSWORD=key_password)
    if args.create:
        if getpass.getpass('Confirm keystore password: ') != password:
            raise RuntimeError('Passwords do not match.')
        key.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        if key.parent.stat().st_uid!=os.geteuid() or key.parent.stat().st_mode & 0o022:
            raise RuntimeError('Use a private directory owned by you, without group/world write access.')
        # Reserve with 0600 permissions before keytool writes it. No key overwrite.
        descriptor=os.open(key,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600);os.close(descriptor)
        key.unlink()  # keytool requires a missing file; the private parent prevents other users writing.
        old_mask=os.umask(0o077)
        try:
            run(['keytool','-genkeypair','-noprompt','-storetype','PKCS12','-keystore',str(key),'-alias',args.alias,
                 '-storepass:env','DRIVER_SETUP_STORE_PASSWORD','-keypass:env','DRIVER_SETUP_KEY_PASSWORD',
                 '-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=Respectlogistic Driver'],env=env)
        finally:
            os.umask(old_mask)
    certificate=run(['keytool','-exportcert','-rfc','-keystore',str(key),'-alias',args.alias,
                     '-storepass:env','DRIVER_SETUP_STORE_PASSWORD'],env=env).decode()
    pem=re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',certificate,re.S)
    if not pem: raise RuntimeError('Signing certificate unavailable.')
    fingerprint=hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem.group())).hexdigest()
    values={'DRIVER_ANDROID_KEYSTORE_BASE64':base64.b64encode(key.read_bytes()),
            'DRIVER_ANDROID_STORE_PASSWORD':password.encode(),'DRIVER_ANDROID_KEY_PASSWORD':key_password.encode(),
            'DRIVER_ANDROID_KEY_ALIAS':args.alias.encode(),'DRIVER_ANDROID_CERT_SHA256':fingerprint.encode()}
    for name,value in values.items():
        run(['gh','secret','set',name,'--repo',REPO],payload=value)
        print(name+': configured')
    print('Permanent certificate SHA256: '+fingerprint)
    print('Keep an independent encrypted backup of '+str(key)+' and its password. Never upload them to the public repository.')
    if args.build:
        run(['gh','workflow','run','android-driver.yml','--repo',REPO,'--ref','respectlogistic/customers'])
        print('Signed APK build requested. Check Actions → Driver Android APK.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--keystore',required=True,help='Private path OUTSIDE the repository')
    parser.add_argument('--alias',default='driver-release')
    parser.add_argument('--create',action='store_true',help='Create a key only for the first release')
    parser.add_argument('--build',action='store_true')
    try: setup(parser.parse_args())
    except (RuntimeError,KeyboardInterrupt) as error:
        print(str(error) or 'Cancelled',file=sys.stderr);sys.exit(1)
