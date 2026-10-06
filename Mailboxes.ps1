$SharedMBs=(Get-ADUser -Filter {msExchRecipientTypeDetails -eq "34359738368"} -Properties msExchRecipientTypeDetails)
#$AllObjects=@()

# RUN ON ROI_SY14


<#
.Synopsis
   Function to audit a file share
.DESCRIPTION
   Designed for official Audit reports
.EXAMPLE
   Audit-FSPerms -SharePath "\\answer\share\Departmental\Legal"
.EXAMPLE
   Another example of how to use this cmdlet
#>

function Audit-SharedMB
{
    [CmdletBinding()]
    Param
    (
        $SharedMailbox
    )
    $SharedMailboxDetails=Get-ADUser $SharedMailbox.samaccountname
    $Perms=Get-MailboxPermission -Identity $SharedMailbox.name|?{$_.User -ne "NT AUTHORITY\SELF"}
    $SAPerms=Get-RecipientPermission -Identity $SharedMailbox.name|?{$_.User -ne "NT AUTHORITY\SELF"}
    $Group=""
    $UserDetails=""
    $ManagerDetails=""
    $AllObjects=@()
    foreach ($Perm in $Perms) {
        $PermissionObject=$Perm.User
        $ADUserObject=Get-ADObject -Filter {userprincipalname -like $PermissionObject}
        $ADGroupObject=Get-ADGroup -Filter {displayname -like $PermissionObject} -Properties displayname
        if ($ADUserObject.ObjectClass -eq "user"){
            $Username=$Perm.User
            $ManagerDetails=""
            $UserDetails=Get-ADuser -filter {UserPrincipalName -like $Username} -Properties Displayname,Mail,Manager
            if ($UserDetails.Manager -notlike $null){
            $ManagerDetails=Get-ADUser $UserDetails.Manager -Properties DisplayName,Mail
            if ($UserDetails.DisplayName -notlike $null){
                $Object= [PSCustomObject]@{
                    'Signoff YES'= $null
                    'Signoff NO' = $null
                    'Data Location Type'="Shared Mailbox"
                    'Data Location'=$SharedMailboxDetails.userprincipalname
                    'AD Group'=$ADGroupObject.DisplayName
                    'Access Type'=((($Perm.AccessRights)[0]).split(','))[0]
                    'User With Access (Name)'=$UserDetails.DisplayName
                    'User With Access (Email)'=$UserDetails.Mail
                    "User's Manager (Name)"=$ManagerDetails.Displayname
                    "User's Manager (Email)"=$ManagerDetails.Mail
                }
                $AllObjects+=$Object
                }
            }
        }
        if ($ADGroupObject.DisplayName -notlike "MBX*" -and $ADGroupObject -notlike $null){
                $Members=Get-ADGroupMember $ADGroupObject.DistinguishedName -Recursive
                foreach ($Member in $Members) {
                    $Object=@()
                    $ManagerDetails=""
                    $UserDetails=""
                    $ADObject=Get-ADObject $Member
                        if ($ADObject.objectClass -eq "user"){
                            $UserDetails=Get-ADUser $Member -Properties Displayname,Mail,Manager
                            if ($UserDetails.Manager -notlike $null){
                                $ManagerDetails=Get-ADUser $UserDetails.Manager -Properties DisplayName,Mail
                            }
                            if ($UserDetails.DisplayName -notlike $null){
                                $Object= [PSCustomObject]@{
                                    'Signoff YES'= $null
                                    'Signoff NO' = $null
                                    'Data Location Type'="Shared Mailbox"
                                    'Data Location'=$SharedMailboxDetails.userprincipalname
                                    'AD Group'=$ADGroupObject.DisplayName
                                    'Access Type'=((($Perm.AccessRights)[0]).split(','))[0]
                                    'User With Access (Name)'=$UserDetails.DisplayName
                                    'User With Access (Email)'=$UserDetails.Mail
                                    "User's Manager (Name)"=$ManagerDetails.Displayname
                                    "User's Manager (Email)"=$ManagerDetails.Mail
                                }
                                $AllObjects+=$Object
                            }
                        }
            }
        }
        if ($ADGroupObject.Displayname -like "MBX*"){
           $TopLevelMembers=Get-ADGroupMember $ADGroupObject
           foreach ($TopLevelMember in $TopLevelMembers){
                if ($TopLevelMember.objectClass -eq "group") {
                    $TopLevelGroup=Get-ADGroup $TopLevelMember -properties DisplayName
                    $TLGMembers=Get-ADGroupMember $TopLevelMember -Recursive
                    foreach ($TLGMember in $TLGMembers){
                        $ManagerDetails=""
                        $UserDetails=Get-ADUser $TLGMember -Properties Displayname,Mail,Manager
                        if ($UserDetails.Manager -notlike $null){
                            $ManagerDetails=Get-ADUser $UserDetails.Manager -Properties DisplayName,Mail
                        }
                        $Object= [PSCustomObject]@{
                            'Signoff YES'= $null
                            'Signoff NO' = $null
                            'Data Location Type'="Shared Mailbox"
                            'Data Location'=$SharedMailboxDetails.userprincipalname
                            'AD Group'=$TopLevelGroup.DisplayName
                            'Access Type'=((($Perm.AccessRights)[0]).split(','))[0]
                            'User With Access (Name)'=$UserDetails.DisplayName
                            'User With Access (Email)'=$UserDetails.Mail
                            "User's Manager (Name)"=$ManagerDetails.Displayname
                            "User's Manager (Email)"=$ManagerDetails.Mail
                        }
                        $AllObjects+=$Object
                    }
                }
                if ($TopLevelMember.objectClass -eq "user") {
                    $TopLevelUser=Get-ADUser $TopLevelMember -properties DisplayName
                    $UserDetails=Get-ADUser $TopLevelUser -Properties Displayname,Mail,Manager
                    $ManagerDetails=""
                    if ($UserDetails.Manager -notlike $null){
                        $ManagerDetails=Get-ADUser $UserDetails.Manager -Properties DisplayName,Mail
                    }
                    $Object= [PSCustomObject]@{
                            'Signoff YES'= $null
                            'Signoff NO' = $null
                            'Data Location Type'="Shared Mailbox"
                            'Data Location'=$SharedMailboxDetails.userprincipalname
                            'AD Group'=$TopLevelGroup.DisplayName
                            'Access Type'=((($Perm.AccessRights)[0]).split(','))[0]
                            'User With Access (Name)'=$UserDetails.DisplayName
                            'User With Access (Email)'=$UserDetails.Mail
                            "User's Manager (Name)"=$ManagerDetails.Displayname
                            "User's Manager (Email)"=$ManagerDetails.Mail
                        }
                        $AllObjects+=$Object
                }
           }
        }
    }
    foreach ($SAPerm in $SAPerms) {
        $PermissionObject=$SAPerm.Trustee
        $ADUserObject=Get-ADObject -Filter {userprincipalname -like $PermissionObject}
        $ADGroupObject=Get-ADGroup -Filter {displayname -like $PermissionObject} -Properties displayname
        if ($ADUserObject.ObjectClass -eq "user"){
            $ManagerDetails=""
            $UserDetails=Get-ADuser $ADUserObject -Properties Displayname,Mail,Manager
            if ($UserDetails.Manager -notlike $null){
            $ManagerDetails=Get-ADUser $UserDetails.Manager -Properties DisplayName,Mail
            }
            $Object= [PSCustomObject]@{
                'Signoff YES'= $null
                'Signoff NO' = $null
                'Data Location Type'="Shared Mailbox"
                'Data Location'=$SharedMailboxDetails.userprincipalname
                'AD Group'=$ADGroupObject.DisplayName
                'Access Type'=((($SAPerm.AccessRights)[0]).split(','))[0]
                'User With Access (Name)'=$UserDetails.DisplayName
                'User With Access (Email)'=$UserDetails.Mail
                "User's Manager (Name)"=$ManagerDetails.Displayname
                "User's Manager (Email)"=$ManagerDetails.Mail
             }
             $AllObjects+=$Object
        }
        if ($ADGroupObject.DisplayName -notlike "MBX*" -and $ADGroupObject -notlike $null){
                $Members=Get-ADGroupMember $ADGroupObject.DistinguishedName -Recursive
                foreach ($Member in $Members) {
                    $Object=@()
                    $ManagerDetails=""
                    $UserDetails=""
                    $ADObject=Get-ADObject $Member
                        if ($ADObject.objectClass -eq "user"){
                            $UserDetails=Get-ADUser $Member -Properties Displayname,Mail,Manager
                            if ($UserDetails.Manager -notlike $null){
                                $ManagerDetails=Get-ADUser $UserDetails.Manager -Properties DisplayName,Mail
                            }
                            if ($UserDetails.DisplayName -notlike $null){
                                $Object= [PSCustomObject]@{
                                    'Signoff YES'= $null
                                    'Signoff NO' = $null
                                    'Data Location Type'="Shared Mailbox"
                                    'Data Location'=$SharedMailboxDetails.userprincipalname
                                    'AD Group'=$ADGroupObject.DisplayName
                                    'Access Type'=((($SAPerm.AccessRights)[0]).split(','))[0]
                                    'User With Access (Name)'=$UserDetails.DisplayName
                                    'User With Access (Email)'=$UserDetails.Mail
                                    "User's Manager (Name)"=$ManagerDetails.Displayname
                                    "User's Manager (Email)"=$ManagerDetails.Mail
                                }
                                $AllObjects+=$Object
                            }
                        }
            }
        }
        if ($ADGroupObject.Displayname -like "MBX*"){
           $TopLevelMembers=Get-ADGroupMember $ADGroupObject
           foreach ($TopLevelMember in $TopLevelMembers){
                if ($TopLevelMember.objectClass -eq "group") {
                    $TopLevelGroup=Get-ADGroup $TopLevelMember -properties DisplayName
                    $TLGMembers=Get-ADGroupMember $TopLevelMember -Recursive
                    foreach ($TLGMember in $TLGMembers){
                        $ManagerDetails=""
                        $UserDetails=Get-ADUser $TLGMember -Properties Displayname,Mail,Manager
                        if ($UserDetails.Manager -notlike $null){
                            $ManagerDetails=Get-ADUser $UserDetails.Manager -Properties DisplayName,Mail
                        }
                        $Object= [PSCustomObject]@{
                            'Signoff YES'= $null
                            'Signoff NO' = $null
                            'Data Location Type'="Shared Mailbox"
                            'Data Location'=$SharedMailboxDetails.userprincipalname
                            'AD Group'=$TopLevelGroup.DisplayName
                            'Access Type'=((($SAPerm.AccessRights)[0]).split(','))[0]
                            'User With Access (Name)'=$UserDetails.DisplayName
                            'User With Access (Email)'=$UserDetails.Mail
                            "User's Manager (Name)"=$ManagerDetails.Displayname
                            "User's Manager (Email)"=$ManagerDetails.Mail
                        }
                        $AllObjects+=$Object
                    }
                }
                if ($TopLevelMember.objectClass -eq "user") {
                    $TopLevelUser=Get-ADUser $TopLevelMember -properties DisplayName
                    $ManagerDetails=""
                    $UserDetails=Get-ADUser $TopLevelUser -Properties Displayname,Mail,Manager
                    if ($UserDetails.Manager -notlike $null){
                        $ManagerDetails=Get-ADUser $UserDetails.Manager -Properties DisplayName,Mail
                    }
                    $Object= [PSCustomObject]@{
                            'Signoff YES'= $null
                            'Signoff NO' = $null
                            'Data Location Type'="Shared Mailbox"
                            'Data Location'=$SharedMailboxDetails.userprincipalname
                            'AD Group'=$TopLevelGroup.DisplayName
                            'Access Type'=((($SAPerm.AccessRights)[0]).split(','))[0]
                            'User With Access (Name)'=$UserDetails.DisplayName
                            'User With Access (Email)'=$UserDetails.Mail
                            "User's Manager (Name)"=$ManagerDetails.Displayname
                            "User's Manager (Email)"=$ManagerDetails.Mail
                        }
                        $AllObjects+=$Object
                }
           }
        }
    }
return $AllObjects|sort 'User With Access (Name)','Access Type' -Unique|Sort 'AD Group'
}

$results = foreach ($mb in $SharedMBs) {
    Audit-SharedMB -SharedMailbox $mb
}

$results | Export-Csv .\out.csv -NoTypeInformation
