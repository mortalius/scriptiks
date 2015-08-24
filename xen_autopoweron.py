#!/usr/bin/python

import subprocess as sp

UUIDList=[]
VM_Autopoweron={}  # uuid:state
VM_Name={}        # uuid:name
PoolID=()

def in_red(text):
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    return FAIL + text + ENDC
def in_blue(text):
    OKBLUE = '\033[94m'
    ENDC = '\033[0m'
    return OKBLUE + text + ENDC
def in_green(text):
    OKGREEN = '\033[92m'
    ENDC = '\033[0m'
    return OKGREEN + text + ENDC


def GetPoolID():
    global PoolID
    cmd_get = "xe pool-list --minimal"
    call_get = sp.Popen(cmd_get.split(),stdout=sp.PIPE)
    state, err = call_get.communicate()
    ID = state.strip('\n')

    cmd_get = "xe pool-param-get uuid=" + ID + " param-name=other-config param-key=auto_poweron"
    call_get = sp.Popen(cmd_get.split(),stdout=sp.PIPE)
    state, err = call_get.communicate()
    swstate = state.strip('\n')

    cmd_get = "xe pool-param-get uuid=" + ID + " param-name=name-label"
    call_get = sp.Popen(cmd_get.split(),stdout=sp.PIPE)
    state, err = call_get.communicate()
    name = state.strip('\n')    
    
    PoolID = (ID,name,swstate)


def GetVMs():
    global VM_Autopoweron
    global VM_Name
    global UUIDList

    # Getting VM UUID List
    cmd_IDList="xe vm-list is-control-domain=false --minimal"
    call_IDList = sp.Popen(cmd_IDList.split(),stdout=sp.PIPE)
    output, err = call_IDList.communicate()
    UUIDList=output.split(',')

    #Getting Name and params of VMs
    for ID in UUIDList:
        cmd_get = "xe vm-param-get uuid="+ID+" param-name=other-config param-key=auto_poweron"
        call_powerstate=sp.Popen(cmd_get.split(),stdout=sp.PIPE,stderr=sp.PIPE)
        state, err = call_powerstate.communicate()
        state=state.strip("\n")
        if state!="true": state=in_red("false")
        VM_Autopoweron.update([(ID,state)])

        cmd_get = "xe vm-param-get uuid="+ID+" param-name=name-label"
        call_name=sp.Popen(cmd_get.split(),stdout=sp.PIPE)
        name, err = call_name.communicate()
        name=name.strip("\n")
        VM_Name.update([(ID,name)])

def PrintVMs():
    print "0. Auto_poweron for pool " + in_blue(PoolID[1]) + " is " + in_green(PoolID[2]) + "\n"
    print "VM Name".center(25)+"VM Auto_poweron"
    i=0
    for ID in UUIDList:
        i+=1
        print "%2d. %25s : %5s" %(i, VM_Name[ID][:25], VM_Autopoweron[ID])

def VM_Switch_autopoweron(ID,switch):
    # ID - UUID
    # switch =0 disables, =1 enables auto_poweron
    if switch==0: sw='false'
    else: sw='true'
    cmd_set = "xe vm-param-set uuid="+ID+" other-config:auto_poweron="+sw
    #xe vm-param-set uuid=e4f904bf-4f04-1b89-8544-5fda378a11bd other-config:auto_poweron=false
    call_set_autopower=sp.Popen(cmd_set.split())

def Pool_Switch_autopoweron(ID,switch):
    if switch==0: sw='false'
    else: sw='true'
    cmd_set = "xe pool-param-set uuid=" + ID + " other-config:auto_poweron=" + sw
    call_set_autopower=sp.Popen(cmd_set.split())    

GetVMs()
GetPoolID()

choice=''
while True:
    PrintVMs()    
    choice=raw_input("Choose VM (x to quit): ")
    if choice=='x': break
    if not choice.isdigit(): continue

    if int(choice) == 0:
        print "Auto_poweron for pool " + in_blue(PoolID[1]) + " is " + in_green(PoolID[2]) + "\n"
        print "1. Enable auto_poweron"
        print "2. Disable auto_poweron"
        print "x. Exit Main"
        choice=raw_input("Choice: ")
        if choice in list('12'):
            if choice=='1': ch=1 
            else: ch=0
            Pool_Switch_autopoweron(PoolID[0],ch)
            GetPoolID()
            raw_input ("Done. Enter to continue..")
        continue

    if int(choice) in range(1,len(UUIDList)+1): 
        ID=UUIDList[int(choice)-1]
        print "VM " + in_red(VM_Name[ID]) + " selected"
        print "Auto_poweron is " + in_red(VM_Autopoweron[ID]) + "\n"
        print "1. Enable auto_poweron"
        print "2. Disable auto_poweron"
        print "x. Exit Main"
        choice=raw_input("Choice: ")
        if choice in list('12'):
            if choice=='1': ch=1 
            else: ch=0
            VM_Switch_autopoweron(ID,ch)
            GetVMs()
            raw_input ("Done. Enter to continue..")
        

	
