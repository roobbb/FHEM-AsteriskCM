# FHEM-AsteriskCM
Callmonitor for Asterisk in FHEM

this module was originally delevoped by marvin78, what you can find here is just a simple fork of the original code from https://github.com/marvin78/FHEM-AsteriskCM/

marvin78 does not maintain or support it anymore, so **please don't bother him** if you have any trouble with his module or the changes you can find here

many thanks to marvin78 for his great module which still works fine and stable - only small changes were necessary because of some changes by Asterisk (e.g. some AMI values changed from upper case to lower, what makes a difference in perl)

### Prerequisites
- Asterisk should already run stable without any issues
- read this https://www.asteriskguru.com/tutorials/manager_conf.html
- FHEM should already run stable without any issues and up to date
- your network should be configured correctly and Asterisk and FHEM should be able to reach each other
- on your Asterisk server go to /etc/asterisk and edit the file "manager.conf", e.g.
  ```
  ;
  ; Asterisk Call Management support
  ;
  
  ; By default asterisk will listen on localhost only.
  [general]
  enabled = yes
  port = 5038
  ;bindaddr = 127.0.0.1
  bindaddr = <ip_of_your_asterisk>
  webenabled = yes
  httptimeout = 60
  
  ; No access is allowed by default.
  ; To set a password, create a file in /etc/asterisk/manager.d
  ; use creative permission games to allow other serivces to create their own
  ; files
  #include "manager.d/*.conf"
  ```
- go into the subdirectory "manager.d" and create a new configfile there (name is not important) and set the rights as the other configs have (in my case asterisk)
    ```
    cd manager.d/
    sudo touch myfile.conf
    sudo chown asterisk:asterisk
    sudo vi myfile.conf
    ```
- enter username you would like, permissions and credentials there - remeber that user and pw - you will need them in FHEM, e.g.
    ```
    [fhem]
    secret = <password_for_fhem>
    deny = 0.0.0.0/0.0.0.0
    permit = 127.0.0.1/255.255.255.255
    ;your LAN should match here
    permit = 192.168.0.1/255.255.255.0
    ;only the rights you want to give
    read = all,system,log,verbose,command,agent,user,config,call
    write = all,system,log,verbose,command,agent,user,config,call
    ```
- save the file and test access via telnet as shown on asteriskguru (link above), only proceed if it works
- if you also enabled asterisks webif (webenabled = yes and of course already configured by http.conf), you can test with it too, type into your browser
  ```
  http://<ip_of_your_asterisk>:<your_http_port>/<your_prefix>/rawman?action=Login&username=<user_from_above>&secret=<password_for_fhem>
  ```
  should give such response:
  ```
  Response: Success
  Message: Authentication accepted
  ```

### Setup in FHEM
- open FHEM's webif and enter "update all https://raw.githubusercontent.com/roobbb/FHEM-AsteriskCM/master/controls_AsteriskCM.txt"
- after that is done consider "reload 72_AsteriskCM" or restart FHEM by "shutdown restart"
- when FHEM is ready define a new device:
  ```
  define myAsteriskCM AsteriskCM <ip_of_your_asterisk> <user_from_above> <port_from_above>
  ```
- in that new created device enter <password_for_fhem> from above after "set myAsteriskCM password" and click set ("password successfully saved" should appear)
- set value for the context attributes as you should have defined in your extensions.conf
  ```
  attr myAsteriskCM contextIncoming <your_incoming_context>
  attr myAsteriskCM contextOutgoing <you_outgoing_context>
  ```
- now click "set ... reconnect" and the state should show "connected"
- so far so good, further attributes may necessary (please read explanations and details you can find when you click "Help for ..." at the bottom of the device's page inside FHEM):
  ```
  attr myAsteriskCM country-code <your_country_code>
  attr myAsteriskCM local-area-code <your_area_code>
  attr myAsteriskCM remove-leading-zero 0
  attr myAsteriskCM reverse-search dasoertliche.de
  attr myAsteriskCM reverse-search-cache 1
  attr myAsteriskCM reverse-search-cache-file /opt/fhem/cache/AsteriskCM_cache.tmp
  attr myAsteriskCM verbose 3
  ```
