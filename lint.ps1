$FolderToCheck = "C:\Users\Wilbur\Documents\boomi-history\components"
$BoomiAccountId = "trainingmredthehorse-ABC12D"
$RulesFileName = 'BoomiSonarQubeRules.xml'


function Run-XPath([xml]$Document, [string]$Xpath) {
    return Select-Xml -XPath $xpath -Xml $Document -Namespace @{"bns" = "http://api.platform.boomi.com/"}
}

function Build-Result([string]$RuleId, [string]$Text, [string]$Level, [xml]$Component) {
    $artifactLocation = @{"uri"="https://platform.boomi.com/AtomSphere.html#build;accountId=" + $BoomiAccountId + ";components=" + $Component.Result.componentId + "~" + $Component.Result.version}
    $physicalLocation = @{"artifactLocation"=$artifactLocation}
    $logicalLocations = @(@{   "name"=$Component.Result.name
                            "fullyQualifiedName"= $Component.Result.folderFullPath + '/' + $Component.Result.name
                        })
    $locations = @(@{   "physicalLocation"=$physicalLocation
                        "logicalLocations"=$logicalLocations
                        })
    $r =  @{
        "level" = $Level
        "ruleId" = $RuleId
        "locations"=$locations
    }
    if ($Text.Length -gt 0) {
        $r.Add("message", @{"text"  = $Text})
    } else {
        $r.Add("message", @{"id"  = "default"})
    }
    return $r
}

function Build-RuleMeta([string]$RuleId, [string]$RuleName, [string]$DefaultMessage) {
    return @{
        "id" = $RuleId
        "name" = $RuleName
        "messageStrings"=@{"default"=@{"text" = $DefaultMessage}}
    }
}



function Format-RulesMeta([Xml]$Rules){
    return ($Rules.profile.rules.rule | %{
            $msg = Select-Xml -Xml $_ -XPath "parameters/parameter[key = 'message']/value"
            Build-RuleMeta -RuleId $_.key -RuleName $_.name -DefaultMessage $msg
        } | ConvertTo-Json -Depth 5
    )
}


function Get-Results([string]$FolderToCheck, [xml]$Rules) {
    $results = [System.Collections.ArrayList]@()
    Get-ChildItem $FolderToCheck -Filter "*.xml" | ForEach-Object {
        [Xml]$component = Get-content (join-path $FolderToCheck $_)
        if ($component.Result.deleted -ne $true) { # ignore things that are deleted
            $Rules.profile.rules.rule | %{
                $expression = Select-Xml -Xml $_ -XPath "parameters/parameter[key = 'expression']/value"
                $r = Run-XPath -Document $component -Xpath $expression
                if ($r) {
                    $j = Build-Result -RuleId $_.key -Level $_.priority -Component $component
                    $count = $results.Add($j)
                }
            }
        }
    }
    return $results
}
function ConvertTo-Sarif([string]$FolderToCheck, [string]$BoomiAccountId, [string]$RulesFileName){
    [Xml]$Rules = Get-content $RulesFileName
    return @"
{
  "version": "2.1.0",
  "
"@ + '$' + @"
schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "boomi-lint",
          "version" : "0.1-alpha",
          "informationUri":"https://google.com",
          "rules" :
"@ +
(Format-RulesMeta -Rules $Rules ) + @"
        }
      },
      "results" : 
"@ + 
( Get-Results -FolderToCheck $FolderToCheck -Rules $Rules | ConvertTo-Json -Depth 5) + @"
    }
  ]
}
"@
}

ConvertTo-Sarif -FolderToCheck $FolderToCheck -BoomiAccountId $BoomiAccountId -RulesFileName $RulesFileName
