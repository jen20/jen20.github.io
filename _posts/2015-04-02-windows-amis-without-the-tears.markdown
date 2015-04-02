--- 
layout: post 
title: "Windows AMIs Without The Tears" 
---

Twice in the last couple of weeks I've helped automate build infrastructure in
AWS, first for [Event Store](https://geteventstore.com) and then secondly for
another company. Both times we got 90% of the way there using great tools like
[Terraform](https://terraform.io) and [Packer](https://packer.io), and fell at
the last hurdle: how do you build Windows images in an automated fashion (i.e.
no point-and-click)?

Asking around some friends in the operations space it appeared this was a
common problem and that even companies with exceptional levels of automation
were still rolling Windows AMIs by hand - at least the first layer. Of course,
the places with really exceptional levels of automation in the operations space
aren't running Windows in the first place, a path I very much recommend.

There are two things at play here: the first is that Windows itself is still
hostile to automation for the most part. Powershell has improved things a lot
once you can actually run scripts on a box, but that doesn't help much during
provisioning. It appears that the Microsoft team just don't "get it" and are
chasing configuration drift management for long-lived servers instead of image
based deployments (and yes, I know about `ConfigurationMode = "ApplyOnly"` in
DSC).

The second is that Amazon do something of a half-assed job when it comes to
Windows. Unlike OpenStack, they don't support X509 certificate pairs during
machine creation, instead opting only for SSH key pairs (more on this later),
for example. They also only let you have one Windows shell script and one
Powershell script to be run during instance bootup. That's not to say that
Azure does any better, but I'll leave that for a future post (or read my
[Twitter stream](https://twitter.com/jen20) for plenty of Azure-direct
vitriol).

So, what's the goal? Here's what I want:

- From my laptop, sat in Bwè Kafe or Macintyre Coffee (RIP) or anywhere
  else for that matter, I want to be able to build a new AMI containing my
  Windows customizations, without having infrastructure up front. That
  means no jump boxes or VPNs should be necessary.

- I want the Packer workflow of defining a set of provisioners on top of a
  series of builders, and allow similar images to be built locally for
  VMWare as well as for AWS. To recap, Packer's templates are JSON files,
  and it is run locally or as part of [Atlas](https://atlas.hashicorp.com)
  or in Jenkins.

- I don't want to resort to installing OpenSSH on Windows, or paying for
  BitVise SSH Server (though these are paths of least resistance).
    
Luckily (!?), to the last point, Windows for a while now has had an
implementation of WS-Management named WinRM. I say luckily because this
protocol is inferior to SSH in every respect I can see, as is fitting for a
member of the WS-\* family. Unluckily, it seems the intended use is in domains,
as the default configuration is for Kerberos authentication over HTTP which is
not ideal for our use case.

It is however possible to configure WinRM for basic authentication over HTTPS
(straightforward enough), or for client certificate based authorization
provided, you are some form of savant who can look past the fact that the only
documentation is in some blog post on what looks like an abandoned site. But
it's OK, we can read through the source code to figure out how it works... oh
wait.

I know that [people in glass houses shouldn't throw
stones](https://docs.geteventstore.com) about this, but seriously, Microsoft is
an 86 billion dollar company and every time I read their documentation I
imagine the internal monologue of the author: "well the option is called
'enable certificate authentication' so I guess the docs can just say 'turning
this on enables certificate authentication' as the detailed explanation - don't
worry, an MVP might write a blog post about it one day and the mystery will be
solved".

It also turns out that [I](https://github.com/mitchellh/packer/issues/451)
[was](https://github.com/mitchellh/packer/issues/1818)
[of](https://github.com/mitchellh/packer/issues/1818)
[course](https://github.com/mitchellh/packer/issues/1977)
[not](https://github.com/mitchellh/packer/issues/1003)
[the](https://github.com/mitchellh/packer/issues/100)
[first](https://github.com/mitchellh/packer/issues/1063)
[person](https://github.com/mitchellh/packer/issues/394) to want this, though I
do not for one second blame the guys at Hashicorp for not doing it and having
to support it.

Luckily however, a community had formed around this problem and had already
done a ton of the work involved:

- [Masterzen](https://github.com/masterzen) implemented a good chunk of the
  WinRM protocol in Go, the language in which Packer is written, in the
  [github.com/masterzen/winrm](https://github.com/masterzen/winrm) package.

- [Dylan Meissner](https://github.com/dylanmei) and [Matt
  Fellows](https://github.com/mefellows) had started the
  [github.com/packer-community](https://github.com/packer-community)
  organization and produced an implementation of copying files over WinRM
  (which it doesn't natively support), and several different types of
  builder including one for AMIs.

So, while hipster-spotting in a coffee house in Austin on a sunny day during
South by Southwest, I thought to myself: "How hard can it be to take this
already pretty mature and feature complete stuff and add some HTTPS
configuration and a way of managing EC2Config? A day, tops, right?". Close to
three weeks on I'm done with it and drained of patience with Microsoft and
Windows and anything to do with Microsoft or Windows, except for this post!

## Step 1 - enabling WinRM over HTTPS and getting a certificate to it

WinRM can be configured to run over HTTPS fairly easily. This is clearly one of
the first steps needed, since we'll need to authenticate against it. When
installing Windows on VMWare or similar you can use the installation
configuration file to run these steps - in EC2 you can make use of user data
for this. After some trial and error, the script turned out to look like this:

```powershell
Write-Host "Disabling WinRM over HTTP..."
Disable-NetFirewallRule -Name "WINRM-HTTP-In-TCP"
Disable-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC"

Start-Process -FilePath winrm `
    -ArgumentList "delete winrm/config/listener?Address=*+Transport=HTTP" `
    -NoNewWindow -Wait

Write-Host "Configuring WinRM for HTTPS..."
Start-Process -FilePath winrm `
    -ArgumentList "set winrm/config @{MaxTimeoutms=`"1800000`"}" `
    -NoNewWindow -Wait

Start-Process -FilePath winrm `
    -ArgumentList "set winrm/config/winrs @{MaxMemoryPerShellMB=`"1024`"}" `
    -NoNewWindow -Wait

Start-Process -FilePath winrm `
    -ArgumentList "set winrm/config/service @{AllowUnencrypted=`"false`"}" `
    -NoNewWindow -Wait

Start-Process -FilePath winrm `
    -ArgumentList "set winrm/config/service/auth @{Basic=`"true`"}" `
    -NoNewWindow -Wait

Start-Process -FilePath winrm `
    -ArgumentList "set winrm/config/service/auth @{CredSSP=`"true`"}" `
    -NoNewWindow -Wait

New-NetFirewallRule -Name "WINRM-HTTPS-In-TCP" `
    -DisplayName "Windows Remote Management (HTTPS-In)" `
    -Description "Inbound rule for Windows Remote Management via WS-Management. [TCP 5986]" `
    -Group "Windows Remote Management" `
    -Program "System" `
    -Protocol TCP `
    -LocalPort "5986" `
    -Action Allow `
    -Profile Domain,Private

New-NetFirewallRule -Name "WINRM-HTTPS-In-TCP-PUBLIC" `
    -DisplayName "Windows Remote Management (HTTPS-In)" `
    -Description "Inbound rule for Windows Remote Management via WS-Management. [TCP 5986]" `
    -Group "Windows Remote Management" `
    -Program "System" `
    -Protocol TCP `
    -LocalPort "5986" `
    -Action Allow `
    -Profile Public

$certContent = "<insert a base 64 encoded version of your certificate here>"

$certBytes = [System.Convert]::FromBase64String($certContent)
$pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$pfx.Import($certBytes, "", "Exportable,PersistKeySet,MachineKeySet")
$certThumbprint = $pfx.Thumbprint
$certSubjectName = $pfx.SubjectName.Name.TrimStart("CN = ").Trim()

$store = new-object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
try {
    $store.Open("ReadWrite,MaxAllowed")
    $store.Add($pfx)

} finally {
    $store.Close()
}

Start-Process -FilePath winrm `
    -ArgumentList "create winrm/config/listener?Address=*+Transport=HTTPS @{Hostname=`"$certSubjectName`";CertificateThumbprint=`"$certThumbprint`";Port=`"5986`"}" `
    -NoNewWindow -Wait

# This part is optional
$user = [adsi]"WinNT://localhost/Administrator,user"
$user.SetPassword("Insert a new Administrator password here")
$user.SetInfo()

Write-Host "Restarting WinRM Service..."
Stop-Service winrm
Set-Service winrm -StartupType "Automatic"
Start-Service winrm
```

Obviously there are some downsides to this. The first is that the script,
possibly complete with base-64 encoded certficicate and desired Administrator
password will be visible in the user-data of the instance Packer creates while
the AMI is being created. The second is that in all likelihood the certificate
will be self signed, so you'll need to provide a root CA cert to the builder do
any meaninful validation against it.

The final downside is that Windows has an extremely limited range of
certificate file formats from which it will import, most notable PCKS#12, or
`*.pfx` as it's commonly known. Although it's possible to generate out all the
necessary certificates in pure Go, there is nothing to convert them into the
PCKS#12 format, though the Azure team do have a library for going the other
way, which suggests that at least one team realises this is a problem.

I have started work on this, but it's not on the critical path - instead you
can use this script if you have OpenSSL available to generate out the pairs
(with no Root CA however) and provide the PFX file path to the builders as you
would if you were using a certificate generated by internal or external PKI.

```bash
set -e

CERTNAME=${1:-packer-winrm-$RANDOM}
SUBJECT="/CN=$CERTNAME"

PFX_FILE=${2:-winrm_server_cert}.pfx
PEM_FILE=${PFX_FILE%.*}.pem

PRIVATE_DIR=`mktemp -d -t packer-certXXXXXX`
chmod 700 $PRIVATE_DIR

EXT_CONF_FILE=`mktemp -t packer-certXXXXXX.conf`

KEY_FILE=$PRIVATE_DIR/cert.key

cat > $EXT_CONF_FILE << EOF
distinguished_name  = req_distinguished_name
[req_distinguished_name]
[v3_req_server]
extendedKeyUsage = serverAuth
EOF

export OPENSSL_CONF=$EXT_CONF_FILE
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -out "$PEM_FILE" \
    -outform PEM -keyout $KEY_FILE -subj "$SUBJECT" \
    -extensions v3_req_server 2> /dev/null

rm $EXT_CONF_FILE
unset OPENSSL_CONF

openssl pkcs12 -export -in "$PEM_FILE" -inkey $KEY_FILE -out "$PFX_FILE" -password pass:""

rm -rf $PRIVATE_DIR

THUMBPRINT=`openssl x509 -inform PEM -in "$PEM_FILE" -fingerprint -noout | \
    sed -e 's/\://g' | sed -n 's/^.*=\(.*\)$/\1/p'`

echo "Certificate Subject: $(echo \"$SUBJECT\" | sed -e 's/\///g')"
echo "Certificate Thumbprint: $THUMBPRINT"
```

## Step 2 - Retrieving the instance password

When AWS instances are started for Windows, you can use the keypair to decrypt
the Administrator password instead of to authenticate like you would on Linux.
This typically takes three to four minutes to become available. Luckily there
is a handy API for it - unluckily it wasn't implemented in the `goamz` library
which Packer uses.

This one was nice and simple, and is a pull request -
[goamz#244](https://github.com/mitchellh/goamz/pull/244). The actual implementation is very small, and will be moot anyway if Packer ever moves to the new go-sdk-aws official library. For completeness, this is what it looks like:

```go
// Response to a GetPasswordData request.
//
// If PasswordData is empty, then one of two conditions is likely: either the
// instance is not running Windows, or the password is not yet available. The
// API documentation suggests that the password should be available within 15
// minutes of launch.
//
// See http://goo.gl/7Dppx0 for more details.
type PasswordDataResponse struct {
	RequestId    string    `xml:"requestId"`
	InstanceId   string    `xml:"instanceId"`
	Timestamp    time.Time `xml:"timestamp"`
	PasswordData string    `xml:"passwordData"`
}

// GetPasswordData retrieves the encrypted administrator password for an
// instance running Windows. The password is encrypted using the key pair,
// so must be decrypted with the corresponding key pair file.
//
// See http://goo.gl/7Dppx0 for more details.
func (ec2 *EC2) GetPasswordData(instId string) (resp *PasswordDataResponse, err error) {
	params := makeParams("GetPasswordData")
	addParamsList(params, "InstanceId", []string{instId})
	resp = &PasswordDataResponse{}
	ec2.query(params, resp)
	if err != nil {
		return nil, err
	}
	return
}
```

## Step 3 - Add steps to the Packer builders for AWS

Two new steps were required

The Packer architecture is such that a series of steps are composed into a builder, which get the machine to the point it can be provisioned using scripts (via remote access), and then shut down and imaged (in the case of EC2). SSH is reasonably heavily built in, but it is possible to reimplement the abstraction of communication for WinRM, which Dylan had already done. Consequently only a few new steps were needed for the Windows builders. The first one generates out the configuration script given known values from the builder configuration:

```go
package common

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"io/ioutil"
	"text/template"

	"github.com/mitchellh/multistep"
	"github.com/mitchellh/packer/packer"

	wincommon "github.com/packer-community/packer-windows-plugins/common"
)

type StepGenerateSecureWinRMUserData struct {
	WinRMConfig          *wincommon.WinRMConfig
	WinRMCertificateFile string
	RunConfig            *RunConfig
}

func (s *StepGenerateSecureWinRMUserData) Run(state multistep.StateBag) multistep.StepAction {
	ui := state.Get("ui").(packer.Ui)

	if !s.RunConfig.ConfigureSecureWinRM {
		return multistep.ActionContinue
	}

	ui.Say("Generating user data for configuring WinRM over TLS...")

	certBytes, err := ioutil.ReadFile(s.WinRMCertificateFile)
	if err != nil {
		ui.Error(fmt.Sprintf("Error reading WinRM certificate file: %s", err))
		return multistep.ActionHalt
	}

	encodedCert := base64.StdEncoding.EncodeToString(certBytes)

	var adminPasswordBuffer bytes.Buffer
	if s.RunConfig.NewAdministratorPassword != "" {
		ui.Say("Configuring user data to change Administrator password...")
		err = changeAdministratorPasswordTemplate.Execute(&adminPasswordBuffer, changeAdministratorPasswordOptions{
			NewAdministratorPassword: s.RunConfig.NewAdministratorPassword,
		})
		if err != nil {
			ui.Error(fmt.Sprintf("Error executing Change Administrator Password template: %s", err))
			return multistep.ActionHalt
		}
	}

	var buffer bytes.Buffer
	err = configureSecureWinRMTemplate.Execute(&buffer, configureSecureWinRMOptions{
		CertificatePfxBase64Encoded:        encodedCert,
		InstallListenerCommand:             installListenerCommand,
		AllowBasicCommand:                  allowBasicCommand,
		AllowUnencryptedCommand:            allowUnencryptedCommand,
		AllowCredSSPCommand:                allowCredSSPCommand,
		MaxMemoryPerShellCommand:           maxMemoryPerShellCommand,
		MaxTimeoutMsCommand:                maxTimeoutMsCommand,
		ChangeAdministratorPasswordCommand: adminPasswordBuffer.String(),
	})
	if err != nil {
		ui.Error(fmt.Sprintf("Error executing Secure WinRM User Data template: %s", err))
		return multistep.ActionHalt
	}

	s.RunConfig.UserData = buffer.String()
	return multistep.ActionContinue
}

func (s *StepGenerateSecureWinRMUserData) Cleanup(multistep.StateBag) {
	// No cleanup...
}

type changeAdministratorPasswordOptions struct {
	NewAdministratorPassword string
}

var changeAdministratorPasswordTemplate = template.Must(template.New("ChangeAdministratorPassword").Parse(`$user = [adsi]"WinNT://localhost/Administrator,user"
$user.SetPassword("{{.NewAdministratorPassword}}")
$user.SetInfo()`))

type configureSecureWinRMOptions struct {
	CertificatePfxBase64Encoded        string
	InstallListenerCommand             string
	AllowBasicCommand                  string
	AllowUnencryptedCommand            string
	AllowCredSSPCommand                string
	MaxMemoryPerShellCommand           string
	MaxTimeoutMsCommand                string
	ChangeAdministratorPasswordCommand string
}

//This is needed to because Powershell uses ` for escapes and there's no straightforward way of constructing
// the necessary escaping in the hash otherwise.
const (
	installListenerCommand = "Start-Process -FilePath winrm -ArgumentList \"create winrm/config/listener?Address=*+Transport=HTTPS @{Hostname=`\"$certSubjectName`\";CertificateThumbprint=`\"$certThumbprint`\";Port=`\"5986`\"}\" -NoNewWindow -Wait"

	allowBasicCommand        = "Start-Process -FilePath winrm -ArgumentList \"set winrm/config/service/auth @{Basic=`\"true`\"}\" -NoNewWindow -Wait"
	allowUnencryptedCommand  = "Start-Process -FilePath winrm -ArgumentList \"set winrm/config/service @{AllowUnencrypted=`\"false`\"}\" -NoNewWindow -Wait"
	allowCredSSPCommand      = "Start-Process -FilePath winrm -ArgumentList \"set winrm/config/service/auth @{CredSSP=`\"true`\"}\" -NoNewWindow -Wait"
	maxMemoryPerShellCommand = "Start-Process -FilePath winrm -ArgumentList \"set winrm/config/winrs @{MaxMemoryPerShellMB=`\"1024`\"}\" -NoNewWindow -Wait"
	maxTimeoutMsCommand      = "Start-Process -FilePath winrm -ArgumentList \"set winrm/config @{MaxTimeoutms=`\"1800000`\"}\" -NoNewWindow -Wait"
)

var configureSecureWinRMTemplate = template.Must(template.New("ConfigureSecureWinRM").Parse(`<powershell>
Write-Host "Disabling WinRM over HTTP..."
Disable-NetFirewallRule -Name "WINRM-HTTP-In-TCP"
Disable-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC"

Start-Process -FilePath winrm -ArgumentList "delete winrm/config/listener?Address=*+Transport=HTTP" -NoNewWindow -Wait

Write-Host "Configuring WinRM for HTTPS..."

.MaxTimeoutMsCommand

.MaxMemoryPerShellCommand

.AllowUnencryptedCommand

.AllowBasicCommand

.AllowCredSSPCommand

New-NetFirewallRule -Name "WINRM-HTTPS-In-TCP" -DisplayName "Windows Remote Management (HTTPS-In)" -Description "Inbound rule for Windows Remote Management via WS-Management. [TCP 5986]" -Group "Windows Remote Management" -Program "System" -Protocol TCP -LocalPort "5986" -Action Allow -Profile Domain,Private

New-NetFirewallRule -Name "WINRM-HTTPS-In-TCP-PUBLIC" -DisplayName "Windows Remote Management (HTTPS-In)" -Description "Inbound rule for Windows Remote Management via WS-Management. [TCP 5986]" -Group "Windows Remote Management" -Program "System" -Protocol TCP -LocalPort "5986" -Action Allow -Profile Public

$certContent = "{{.CertificatePfxBase64Encoded}}"

$certBytes = [System.Convert]::FromBase64String($certContent)
$pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$pfx.Import($certBytes, "", "Exportable,PersistKeySet,MachineKeySet")
$certThumbprint = $pfx.Thumbprint
$certSubjectName = $pfx.SubjectName.Name.TrimStart("CN = ").Trim()

$store = new-object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
try {
    $store.Open("ReadWrite,MaxAllowed")
    $store.Add($pfx)

} finally {
    $store.Close()
}

.InstallListenerCommand

.ChangeAdministratorPasswordCommand

Write-Host "Restarting WinRM Service..."
Stop-Service winrm
Set-Service winrm -StartupType "Automatic"
Start-Service winrm
</powershell>`))
```

The second is a new step to get the source instance password as it becomes available:

```go
package common

import (
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"log"
	"time"

	"code.google.com/p/gosshold/ssh/terminal"

	"github.com/mitchellh/goamz/ec2"
	"github.com/mitchellh/multistep"
	"github.com/mitchellh/packer/packer"

	wincommon "github.com/packer-community/packer-windows-plugins/common"
)

type StepGetPassword struct {
	WinRMConfig        *wincommon.WinRMConfig
	RunConfig          *RunConfig
	GetPasswordTimeout time.Duration
}

func (s *StepGetPassword) Run(state multistep.StateBag) multistep.StepAction {
	ui := state.Get("ui").(packer.Ui)
	instance := state.Get("instance").(*ec2.Instance)

	if s.RunConfig.NewAdministratorPassword != "" {
		s.WinRMConfig.WinRMPassword = s.RunConfig.NewAdministratorPassword
		return multistep.ActionContinue
	}

	var password string
	var err error

	cancel := make(chan struct{})
	waitDone := make(chan bool, 1)
	go func() {
		ui.Say(fmt.Sprintf("Retrieving auto-generated password for instance %s...", instance.InstanceId))

		password, err = s.waitForPassword(state, cancel)
		if err != nil {
			waitDone <- false
			return
		}
		waitDone <- true
	}()

	log.Printf("Waiting to retrieve instance %s password, up to timeout: %s", instance.InstanceId, s.GetPasswordTimeout)
	timeout := time.After(s.GetPasswordTimeout)

WaitLoop:
	for {
		// Wait for one of: the password becoming available, a timeout occuring
		// or an interrupt coming through.
		select {
		case <-waitDone:
			if err != nil {
				state.Put("error", err)
				ui.Error(err.Error())
				return multistep.ActionHalt
			}

			s.WinRMConfig.WinRMPassword = password
			break WaitLoop

		case <-timeout:
			err := fmt.Errorf(fmt.Sprintf("Timeout retrieving password for instance %s", instance.InstanceId))
			state.Put("error", err)
			ui.Error(err.Error())
			close(cancel)
			return multistep.ActionHalt

		case <-time.After(1 * time.Second):
			if _, ok := state.GetOk(multistep.StateCancelled); ok {
				// Build was cancelled.
				close(cancel)
				log.Println("Interrupt detected, cancelling password retrieval")
				return multistep.ActionHalt
			}
		}
	}

	return multistep.ActionContinue

}

func (s *StepGetPassword) waitForPassword(state multistep.StateBag, cancel <-chan struct{}) (string, error) {
	ec2conn := state.Get("ec2").(*ec2.EC2)
	instance := state.Get("instance").(*ec2.Instance)
	privateKey := state.Get("privateKey").(string)

	for {
		select {
		case <-cancel:
			log.Println("Retrieve password wait cancelled. Exiting loop.")
			return "", errors.New("Retrieve password wait cancelled")

		case <-time.After(20 * time.Second):
		}

		resp, err := ec2conn.GetPasswordData(instance.InstanceId)
		if err != nil {
			err := fmt.Errorf("Error retrieving auto-generated instance password: %s", err)
			return "", err
		}

		if resp.PasswordData != "" {
			decryptedPassword, err := decryptPasswordDataWithPrivateKey(resp.PasswordData, []byte(privateKey))
			if err != nil {
				err := fmt.Errorf("Error decrypting auto-generated instance password: %s", err)
				return "", err
			}
			return decryptedPassword, nil
		}
	}
}

func (s *StepGetPassword) Cleanup(multistep.StateBag) {
	// No cleanup...
}

func decryptPasswordDataWithPrivateKey(passwordData string, pemBytes []byte) (string, error) {
	encryptedPasswd, err := base64.StdEncoding.DecodeString(passwordData)
	if err != nil {
		return "", err
	}

	block, _ := pem.Decode(pemBytes)
	var asn1Bytes []byte
	if _, ok := block.Headers["DEK-Info"]; ok {
		fmt.Printf("Encrypted private key. Please enter passphrase: ")
		password, err := terminal.ReadPassword(0)
		fmt.Printf("\n")
		if err != nil {
			return "", err
		}

		asn1Bytes, err = x509.DecryptPEMBlock(block, password)
		if err != nil {
			return "", err
		}
	} else {
		asn1Bytes = block.Bytes
	}

	key, err := x509.ParsePKCS1PrivateKey(asn1Bytes)
	if err != nil {
		return "", err
	}

	out, err := rsa.DecryptPKCS1v15(nil, key, encryptedPasswd)
	if err != nil {
		return "", err
	}

	return string(out), nil
}
```

All well and good. Adding them into the Windows builder pipeline gives us
something that looks like this (in this case for building AMIs backed by EBS):

```go
	// Build the steps
	steps := []multistep.Step{
		&winawscommon.StepGenerateSecureWinRMUserData{
			RunConfig:            &b.config.RunConfig,
			WinRMConfig:          &b.config.WinRMConfig,
			WinRMCertificateFile: b.config.WinRMCertificateFile,
		},
		&awscommon.StepSourceAMIInfo{
			SourceAmi:          b.config.SourceAmi,
			EnhancedNetworking: b.config.AMIEnhancedNetworking,
		},
		&awscommon.StepKeyPair{
			Debug:          b.config.PackerDebug,
			DebugKeyPath:   fmt.Sprintf("ec2_%s.pem", b.config.PackerBuildName),
			KeyPairName:    b.config.TemporaryKeyPairName,
			PrivateKeyFile: b.config.KeyPairPrivateKeyFile,
		},
		&winawscommon.StepSecurityGroup{
			SecurityGroupIds: b.config.SecurityGroupIds,
			WinRMPort:        b.config.WinRMPort,
			VpcId:            b.config.VpcId,
		},
		&winawscommon.StepRunSourceInstance{
			Debug:              b.config.PackerDebug,
			ExpectedRootDevice: "ebs",
			BlockDevices:       &b.config.BlockDevices,
			RunConfig:          &b.config.RunConfig,
		},
		&winawscommon.StepGetPassword{
			WinRMConfig:        &b.config.WinRMConfig,
			RunConfig:          &b.config.RunConfig,
			GetPasswordTimeout: 5 * time.Minute,
		},
		winawscommon.NewConnectStep(ec2conn, b.config.WinRMPrivateIp, &b.config.WinRMConfig),
		&common.StepProvision{},
		&stepStopInstance{SpotPrice: b.config.SpotPrice},
		// TODO(mitchellh): verify works with spots
		&stepModifyInstance{},
		&stepCreateAMI{},
		&awscommon.StepAMIRegionCopy{
			Regions: b.config.AMIRegions,
		},
		&awscommon.StepModifyAMIAttributes{
			Description: b.config.AMIDescription,
			Users:       b.config.AMIUsers,
			Groups:      b.config.AMIGroups,
		},
		&awscommon.StepCreateTags{
			Tags: b.config.AMITags,
		},
	}
```

After applying this an a number of other refactorings and rolling the
underlying library support for HTTPS, ignoring certificate chain validation and
validating against a CA root through the rest of the components, we can take a
template like this...

```json
{
    "builders": [
        {
            "type": "amazon-windows-ebs",
            "region": "us-east-1",
            "source_ami": "ami-b27830da",
            "instance_type": "t2.micro",
            "ami_name": "windows-ami-{{timestamp}}",
            "associate_public_ip_address":true,
            
            "winrm_username": "Administrator",
            "winrm_wait_timeout": "10m",
            "winrm_autoconfigure": true,
            "winrm_certificate_file": "winrm_server_cert.pfx",
            "winrm_ignore_cert_chain": true
        }
    ],
    "provisioners": [
        {
            "type": "powershell",
            "inline": [
                "dir c:\\"
            ]
        }
    ]
}
```

...and build an AMI out of it!

Obviously the provisioning script here is trivial, but it could do whatever it
needs to. File provisioners and Windows Shell provisioners also work, as well
as a new type called a "Restart Windows" provisioner.

Adding in the configuration directive `"new_administrator_password":
"Derp1234''''"` as part of the builder, we could short circuit the need to wait
for the instance password to become available, though it's not much longer in
practice than it takes WinRM to become available.

An example run of this gives the following output (in us-east-1, since AMIs are
region specific):

```
$ packer build test.json
amazon-windows-ebs output will be in this color.

==> amazon-windows-ebs: Generating user data for configuring WinRM over TLS...
==> amazon-windows-ebs: Inspecting the source AMI...
==> amazon-windows-ebs: Creating temporary keypair: packer 551d86b2-983a-c071-79fc-ba9022283cd4
==> amazon-windows-ebs: Creating temporary security group for this instance...
==> amazon-windows-ebs: Authorizing WinRM access on the temporary security group...
==> amazon-windows-ebs: Launching a source AWS instance...
    amazon-windows-ebs: Instance ID: i-73e0c15c
==> amazon-windows-ebs: Waiting for instance (i-73e0c15c) to become ready...
==> amazon-windows-ebs: Retrieving auto-generated password for instance i-73e0c15c...
==> amazon-windows-ebs: Waiting for WinRM to become available...
==> amazon-windows-ebs: Connected to WinRM!
==> amazon-windows-ebs: Provisioning with Powershell...
==> amazon-windows-ebs: Provisioning with shell script: /var/folders/bp/j3md7xwj3js6skcq6_3vx4z40000gn/T/packer-powershell-provisioner082516315
    amazon-windows-ebs:
    amazon-windows-ebs:
    amazon-windows-ebs: Directory: C:\
    amazon-windows-ebs:
    amazon-windows-ebs:
    amazon-windows-ebs: Mode                LastWriteTime     Length Name
    amazon-windows-ebs: ----                -------------     ------ ----
    amazon-windows-ebs: d----         8/22/2013   3:52 PM            PerfLogs
    amazon-windows-ebs:
    amazon-windows-ebs: d-r--        10/15/2014   5:58 AM            Program Files
    amazon-windows-ebs: d----         2/10/2015  10:20 PM            Program Files (x86)
    amazon-windows-ebs: d-r--          4/2/2015   6:15 PM            Users
    amazon-windows-ebs: d----          4/2/2015   3:44 PM            Windows
    amazon-windows-ebs:
    amazon-windows-ebs:
==> amazon-windows-ebs: Stopping the source instance...
==> amazon-windows-ebs: Waiting for the instance to stop...
==> amazon-windows-ebs: Creating the AMI: windows-ami-1427998386
    amazon-windows-ebs: AMI: ami-a02514c8
==> amazon-windows-ebs: Waiting for AMI to become ready...
==> amazon-windows-ebs: Terminating the source AWS instance...
==> amazon-windows-ebs: Deleting temporary security group...
==> amazon-windows-ebs: Deleting temporary keypair...
Build 'amazon-windows-ebs' finished.

==> Builds finished. The artifacts of successful builds are:
--> amazon-windows-ebs: AMIs were created:

us-east-1: ami-a02514c8 
```

## What's Left?

There are a number of features not on the critical path that need finishing off
to consider this "complete". The ones I can think of offhand are:

- Generate out the certificates automatically if one isn't specified

- Support all the different types of provisioners with bootstrapping code

- Support EC2Config configuration in the builder such that we can build layers
  of images. For example, the base image for an organization might consist of
  Windows, IIS, the Boundary meter and Hekad. This can then be built upon by
  several different subsequent packer runs to deploy your actual software in an
  image-based fashion.

The script which will need executing for EC2Config is straightforward:

```powershell
function Format-XML ([xml]$xml, $indent=2) 
{ 
    $StringWriter = New-Object System.IO.StringWriter 
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter 
    $xmlWriter.Formatting = "indented" 
    $xmlWriter.Indentation = $Indent 
    $xml.WriteContentTo($XmlWriter) 
    $XmlWriter.Flush() 
    $StringWriter.Flush() 
    Write-Output $StringWriter.ToString() 
}

$ec2ConfigPath = Join-Path (Get-Item Env:\ProgramFiles).Value "Amazon\Ec2ConfigService\Settings"

$ec2ConfigFile = Join-Path $ec2ConfigPath "Config.xml"
$ec2BundleConfigFile = Join-Path $ec2ConfigPath "BundleConfig.xml"

#EC2Config
[xml]$config = Get-Content -Path $ec2ConfigFile
foreach ($t in $config.EC2ConfigurationSettings.Plugins.Plugin) {
    if ($t.Name -eq "Ec2SetPassword") {
        $t.State = "{{.EC2SetPassword}}"
    }
    if ($t.Name -eq "Ec2HandleUserData") {
        $t.State = "{{.EC2HandleUserData}}"
    }
}
Format-XML $config.InnerXml | Set-Content -Path $ec2ConfigFile

[xml]$bundleConfig = Get-Content -Path $ec2BundleConfigFile
foreach ($t in $bundleConfig.BundleConfig.Property) {
    if ($t.Name -eq "AutoSysprep") {
        $t.Value = "{{.AutoSysPrep}}"
    }
    if ($t.Name -eq "SetPasswordAfterSysprep") {
        $t.Value = "{{.SetPasswordAfterSysprep}}"
    }
}
Format-XML $bundleConfig.InnerXml | Set-Content -Path $ec2BundleConfigFile
```

## Summary

This should be easier - way easier. Building images should not need a ton of
extra software just to support Windows. But then again, doing a ton of extra
stuff just to make Windows work is hardly a novelty to people who ever have to
work with it.

The initial work done on this by Matt, Dylan and Masterzen (not sure on the
real name there!) was outstanding, and I'm happy to have been able to
contribute to it and to be able to slightly improve the conditions for people
unfortunate enough to need to deploy Windows somewhat. And most of all, I'm
happy that my Teamcity build agents can now build future versions of
themselves.

For now the pull request still depends on my custom fork of `goamz` so hasn't
been merged, and so this stuff is hard to build. Hopefully we'll get this stuff
merged and get a release out soon!
