param(
    [Parameter(mandatory=$true)][String] $ResourceGroupName,
    [Parameter(mandatory=$true)][String] $StorageAccount,
    [String] $ContainerName="insights-metrics-pt1m",
    [int]$SearchTime=1,  #探索する期間、$SearchTime以内、単位は時間 
    [int]$BasedTime=24  #基準とする期間、$SearchTime以内、単位は時間 
)



# Functions
Function Check-DiagnosticLog{
    Param(
        [Parameter(Mandatory=$True)]$resourceGroup,
        [Parameter(Mandatory=$True)]$storageAccount,
        [Parameter(Mandatory=$true)]$containerName,
        [Parameter(Mandatory=$True)]$searchTime,
        [Parameter(Mandatory=$True)]$basedTime
    )
    
    if($searchTime -ge $basedTime){
        Write-Output "Error. BasedTime need to be bigger than SearchTime."
        Exit 1
    }

    $saContext = (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount).Context

    $utcDateTime = (Get-Date).ToUniversalTime()    #現在時刻を世界協定時間に変更
    $utcDateTime_SearchTime = (Get-Date).ToUniversalTime().addhours(-$searchTime) #探索するBlobの時間範囲
    $utcDateTime_BasedTime = (Get-Date).ToUniversalTime().addhours(-$basedTime) #探索の基準とするBlobの時間範囲


    #基準期間（ex.24時間前から現在時刻）にかけて編集された Blob ファイルの取得
    $PreviousBlobs = Get-AzStorageBlob -Container $containerName -Context $saContext | ? {$_.LastModified -ge $utcDateTime_BasedTime}

    #上記から探索期間（ex.1時間前から現在時刻）にかけて編集された Blob ファイルの取得
    $CurrentBlobs = $PreviousBlobs | ? {$_.LastModified -ge $utcDateTime_SearchTime}
    
    #NICの名前までのプレフィックスを新しい配列に格納
    $pre_blobs = @()
    foreach ($Blob in $PreviousBlobs) {
        if($Blob.Name.Contains("NETWORKINTERFACES")){
            $pre_blobs += Split-Path -Parent $Blob.Name | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Leaf #task : きれいにする
        }
    }
    $cur_blobs = @()
    foreach ($Blob in $CurrentBlobs) {
        if($Blob.Name.Contains("NETWORKINTERFACES")){
            $cur_blobs += Split-Path -Parent $Blob.Name | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Leaf #task : きれいにする
        }
    }
  
    #重複するものを削除
    #$pre_blobs = $pre_blobs | select Name | Sort-Object | Get-Unique -AsString  
    #$cur_blobs = $cur_blobs | select Name | Sort-Object | Get-Unique -AsString
    
    $pre_blobs = $pre_blobs | Sort-Object | Get-Unique -AsString  
    $cur_blobs = $cur_blobs | Sort-Object | Get-Unique -AsString


    $Result = @()
    #期間内にNICが増えて、同じ数だけ減ってしまうとBlobの数では比較できないので、名前で確認する
    foreach ($Previous in $pre_blobs) {
        $Flag = $False
        foreach ($Current in $cur_blobs) {
            if($Previous -eq $Current){
                $Flag = $True
                break
            }
        }
        if($Flag -eq $False){
            #task : エラー発覚
            #Write-Output "Info $Previous log stopped"
            $Result += $Previous
        }
    }

    if($Result.Length -eq 0 ){
        #Write-Output "All NIC Log is Fine"
        return $True
    }else{
        #Write-Output "$Result log stopped"
        return $Result
    }
}


#Function
Function Check-Parameters{
    Param(
        $RGName,
        $SAName
    )

    # Check RG exist
    if ( ($RGName -ne $null) -and ($RGName -ne "") ){
        $RG=Get-AzResourceGroup -name $RGName -ErrorAction SilentlyContinue
        if ($RG -eq $null){
            Write-Output "Error. Resource Group ($RGName) is not exist. Script aborted."
            exit 1
        }
    }else {
        Write-Output "Error. Resource Group ($RGName) is not exist. Script aborted."
        exit 1
    }

     # Check Storage Account exist
     if ( ($SAName -ne $null) -and ($SAName -ne "") ){
        $SA=Get-AzStorageAccount -ResourceGroupName $RGName | Select-Object ResourceGroupName,StorageAccountName 
        if ($SA -eq $null){
            Write-Output "Error. ResourceGroup($RGName) is not found in this Subscription"
            exit 1
        }
    }else {
        Write-Output "Error. ResourceGroup($RGName) is not found in this Subscription"
        exit 1
    }
    
}


# -- Starting Script
Write-Output "Info. Script started"

 # 自動作成された接続資産（実行アカウント）を利用して Azure にログイン
try {
    $automationConnectionName = "AzureRunAsConnection"
    $connection = Get-AutomationConnection -Name $automationConnectionName

    Write-Output "# Logging in to Azure..."

    $account = Add-AzAccount `
        -ServicePrincipal `
        -TenantId $connection.TenantId `
        -ApplicationId $connection.ApplicationId `
        -CertificateThumbprint $connection.CertificateThumbprint

    Write-Output "Done."
}
catch {
    if (!$connection) {
        throw "Connection $automationConnectionName not found."
    } else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}


Write-Output "Info. Start Checking Log existence"

Check-Parameters $ResourceGroupName $StorageAccount

$log_result = Check-DiagnosticLog $ResourceGroupName $StorageAccount $ContainerName $SearchTime $BasedTime

if($log_result -eq $True){
    Write-Output "All NIC Log is Fine"
}else{
    Write-Output "$log_result log stopped"
}

