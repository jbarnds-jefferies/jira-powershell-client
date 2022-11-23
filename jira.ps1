$servers = @{
    jefferies = [ServerData]::new(
        "https://jirappw01",
        [Token]::new($JIRA_COOKIE, [TokenType]::cookie)
    )
}

class JiraClient: ICloneable {
    [string] $base_url
    hidden [Token] $token

    JiraClient(
        [ServerData] $server
    ) {
        $this.base_url = $server.base_url
        $this.token = $server.token
    }

    JiraClient(
        [string] $base_url,
        [Token] $token
    ) {
        $this.base_url = $base_url
        $this.token = $token
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject]
    get_project(
        [string] $project_id_or_key
    ) {
        $headers = $this.get_default_headers()
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/project/$($project_id_or_key)"
            Method          = "GET"
            Headers         = $headers 
            ContentType     = "application/json; charset=utf-8"
        }       

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject]
    get_projects() {
        $headers = $this.get_default_headers()
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/project/recent"
            Method          = "GET"
            Headers         = $headers 
            ContentType     = "application/json; charset=utf-8"
        }       

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    create_project(
        [Project] $project
    ) {
        $headers = $this.get_default_headers()
        $headers.Add("cache-control", "no-cache")
        $body = @{

        }
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/project"
            Method          = "POST" 
            Headers         = $headers
            Body            = $body
            ContentType     = "application/json; charset=utf-8"
        }

        return Invoke-WebRequest @parameters
    }
    
    [void] get_issues(
        [string] $project_name, 
        [int] $chunk_size
    ) {
        $issues = @() 
        $response = $this.get_issue_chunk($project_name, 0, $chunk_size).Content | ConvertFrom-Json  
        $total_issues = $response.total
        0..($chunk_size -1) | ForEach-Object {
            $issues += $response.issues[$_]
        }

        $path = "$(Get-Location)\..\data\$($project_name)\issues-chunk-1.json"
        $content = ConvertTo-Json -Depth 10 -InputObject $issues
        Set-Content -Path $path -Value $content

        $runspace_pool = [runspacefactory]::CreateRunspacePool(1, 10)
        $runspace_pool.Open()
        $jobs = @()
            
        $script_block = {
            param(
                $client,
                $project_name, 
                $chunk_index, 
                $chunk_size,
                $working_directory
            )

            $issues = @()
            $response = $client.get_issue_chunk($project_name, ($chunk_index - 1) * $chunk_size, $chunk_size).Content | ConvertFrom-Json  
            0..($chunk_size -1) | ForEach-Object {
                $issues += $response.issues[$_]
            }

            $path = "$working_directory\..\data\$($project_name)\issues-chunk-$chunk_index.json"
            $content = ConvertTo-Json -Depth 10 -InputObject $issues
            Set-Content -Path $path -Value $content 
        }
        
        $working_directory = Get-Location
        $proceeding_chunks = [math]::Floor($total_issues / $chunk_size)
        2..10 | ForEach-Object {
            $script = [powershell]::Create()
            $script.RunspacePool = $runspace_pool
            $script.AddScript($script_block).AddParameters(@($this, $project_name, $_, $chunk_size, $working_directory))
            $jobs += $script.BeginInvoke()
        }

        function update_status() {
            $completed = $jobs.IsCompleted.Where({$_ -eq $True}).Count + 1
            $progress = $completed / $proceeding_chunks * 100

            Write-Progress -Activity "Requesting $total_issues issues from $project_name" -Status "$($completed * 50)/$total_issues" -PercentComplete $progress  
        }

        while ($jobs.IsCompleted -contains $false) {
            update_status($jobs)
            Start-Sleep 1
        }
    }

    [void] get_issues([string] $project_name) {
        $this.get_issues($project_name, 50)
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    get_issue_chunk(
        [string] $project_name, 
        [int] $start_at,
        [int] $size
    ) {
        $headers = $this.get_default_headers()
        $body = @{
            jql = "project = $($project_name)"
            startAt = $start_at 
            maxResults = $size   
        } | ConvertTo-Json  
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/search"
            Method          = "POST"
            Headers         = $headers 
            Body            = $body
            ContentType     = "application/json; charset=utf-8"
        } 

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    create_issue(
        [Issue] $issue
    ) {
        $headers = $this.get_default_headers()
        $body = $issue.to_json_body()
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/issue"
            Method          = "POST"
            Headers         = $headers 
            Body            = $body
            ContentType     = "application/json; charset=utf-8"
        }

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    update_issue(
        [string] $issue_key,
        [System.Collections.Hashtable] $fields
    ) {
        $headers = $this.get_default_headers()
        $body = @{
            fields = $fields 
        } | ConvertTo-Json 
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/issue/$($issue_key)"
            Method          = "PUT"
            Headers         = $headers 
            Body            = $body
            ContentType     = "application/json; charset=utf-8"
        }

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    get_fields() {
        $headers = $this.get_default_headers()
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/field"
            Method          = "GET"
            Headers         = $headers 
            ContentType     = "application/json; charset=utf-8"
        }

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    create_field(
        [Field] $field
    ) {
        $headers = $this.get_default_headers()
        $body = $field.to_json_body()
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/field"
            Method          = "POST"
            Headers         = $headers 
            Body            = $body
            ContentType     = "application/json; charset=utf-8"
        }

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    get_field_context(
        [string] $fieldId
    ) {
        $headers = $this.get_default_headers()
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/field/customfield_$($fieldId)/context"
            Method          = "GET"
            Headers         = $headers 
            ContentType     = "application/json; charset=utf-8"
        }

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    create_field_context(
        [FieldContext] $fieldContext,
        [string] $fieldId
    ) {
        $headers = $this.get_default_headers()
        $body = $fieldContext.to_json_body()
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/field/customfield_$($fieldId)/context"
            Method          = "POST"
            Headers         = $headers 
            Body            = $body
            ContentType     = "application/json; charset=utf-8"
        }

        return Invoke-WebRequest @parameters 
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    get_field_options(
        [string] $issue_key 
    ) {
        $headers = $this.get_default_headers()
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/issue/$($issue_key)/editmeta"
            Method          = "GET"
            Headers         = $headers 
            ContentType     = "application/json; charset=utf-8"
        } 

        return Invoke-WebRequest @parameters
    }

    [Microsoft.PowerShell.Commands.HtmlWebResponseObject] 
    create_field_options(
        [FieldOption[]] $fieldOptions,
        [string] $fieldId,
        [string] $contextId
    ) {
        $headers = $this.get_default_headers()
        $body = @{options = $fieldOptions} | ConvertTo-Json
        $parameters = [ordered] @{
            Uri             = "$($this.base_url)/field/customfield_$($fieldId)/context/$($contextId)/option"
            Method          = "POST"
            Headers         = $headers 
            Body            = $body
            ContentType     = "application/json; charset=utf-8"
        }

        return Invoke-WebRequest @parameters 
    }

    hidden [System.Collections.Hashtable] get_default_headers() {
        if (-Not $this.token.ty -eq [TokenType]::Cookie) {
            return @{ Authorization = $this.token.to_header() }
        }
                
        return @{ Cookie = $this.token.to_header() }
    }

    hidden [System.Collections.Hashtable]
    onvert_to_hashtable([string] $input_object) {
        if ($null -eq $input_object) {
            return $null
        }

        if ($input_object -is [System.Collections.IEnumerable] -and $input_object -isnot [string]) {
            $collection = @(
                foreach ($object in $input_object) {
                    $this.convert_to_hashtable($object)
                }
            )

            return $collection
        } 
        
        if ($input_object -is [psobject]) { 
            $hash = @{}
            foreach ($property in $input_object.PSObject.Properties) {
                $hash[$property.Name] = $this.convert_to_hashtable($property.Value)
            }

            return $hash
        } 
        
        return $input_object
    }
}

class ServerData: ICloneable {
    [string] $base_url
    [Token] $token

    ServerData(
        [string] $base_url,
        [Token] $token
    ) {
        $this.base_url = $base_url
        $this.token = $token
    }

    [Object] Clone() {
        return [ServerData]::new($this.ServerData, $this.token.Clone())
    }
}

enum TokenType {
    Bearer
    Basic
    Cookie
}

class Token: ICloneable {
    hidden [string] $inner
    [TokenType] $ty

    Token(
        [string] $inner,
        [TokenType] $ty
    ) {
        $this.inner = $inner
        $this.ty = $ty
    }

    [string] to_header() {
        if ($this.ty.Equals([TokenType]::Bearer)) {
            return "Bearer $($this.inner)"
        } else if ($this.ty.Equals([TokenType]::Basic)) {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($this.inner)
            $EncodedText = [Convert]::ToBase64String($Bytes)
            return "Basic $EncodedText"
        } else {
            return $this.inner            
        }
    }

    [Object] Clone() {
        return [Token]::new($this.inner, $this.ty)
    }
}

Class FieldType {
    [string] $cascadingselect = "com.atlassian.jira.plugin.system.customfieldtypes:cascadingselect"
    [string] $datepicker = "com.atlassian.jira.plugin.system.customfieldtypes:datepicker"
    [string] $datetime = "com.atlassian.jira.plugin.system.customfieldtypes:datetime"
    [string] $float = "com.atlassian.jira.plugin.system.customfieldtypes:float"
    [string] $grouppicker = "com.atlassian.jira.plugin.system.customfieldtypes:grouppicker"
    [string] $importid = "com.atlassian.jira.plugin.system.customfieldtypes:importid"
    [string] $labels = "com.atlassian.jira.plugin.system.customfieldtypes:labels"
    [string] $multicheckboxes = ""
    [string] $multigrouppicker = ""
    [string] $multiselect = "com.atlassian.jira.plugin.system.customfieldtypes:multicheckboxes"
    [string] $multiuserpicker = "com.atlassian.jira.plugin.system.customfieldtypes:multigrouppicker"
    [string] $multiversion = "com.atlassian.jira.plugin.system.customfieldtypes:multiversion"
    [string] $project  = "com.atlassian.jira.plugin.system.customfieldtypes:project"
    [string] $radiobuttons = "com.atlassian.jira.plugin.system.customfieldtypes:radiobuttons"
    [string] $readonlyfield = "com.atlassian.jira.plugin.system.customfieldtypes:readonlyfield"
    [string] $select = "com.atlassian.jira.plugin.system.customfieldtypes:select"
    [string] $textarea = "com.atlassian.jira.plugin.system.customfieldtypes:textarea"
    [string] $textfield = "com.atlassian.jira.plugin.system.customfieldtypes:textfield"
    [string] $url = "com.atlassian.jira.plugin.system.customfieldtypes:url"
    [string] $userpicker = "com.atlassian.jira.plugin.system.customfieldtypes:userpicker"
    [string] $version = "com.atlassian.jira.plugin.system.customfieldtypes:version"
}

Class SearcherKey {
    [string] $cascadingselect = "com.atlassian.jira.plugin.system.customfieldtypes:cascadingselectsearcher"
    [string] $datepicker = "com.atlassian.jira.plugin.system.customfieldtypes:daterange"
    [string] $datetime = "com.atlassian.jira.plugin.system.customfieldtypes:datetimerange"
    [string] $float =  "com.atlassian.jira.plugin.system.customfieldtypes:exactnumber"
    [string] $grouppicker = "com.atlassian.jira.plugin.system.customfieldtypes:grouppickersearcher"
    [string] $importid = "com.atlassian.jira.plugin.system.customfieldtypes:exactnumber"
    [string] $labels = "com.atlassian.jira.plugin.system.customfieldtypes:labelsearcher"
    [string] $multicheckboxes = "com.atlassian.jira.plugin.system.customfieldtypes:multiselectsearcher"
    [string] $multigrouppicker = "com.atlassian.jira.plugin.system.customfieldtypes:multiselectsearcher"
    [string] $multiselect = "com.atlassian.jira.plugin.system.customfieldtypes:multiselectsearcher"
    [string] $multiuserpicker = "com.atlassian.jira.plugin.system.customfieldtypes:userpickergroupsearcher"
    [string] $multiversion = "com.atlassian.jira.plugin.system.customfieldtypes:versionsearcher"
    [string] $project = "com.atlassian.jira.plugin.system.customfieldtypes:projectsearcher"
    [string] $radiobuttons = "com.atlassian.jira.plugin.system.customfieldtypes:multiselectsearcher"
    [string] $readonlyfield = "com.atlassian.jira.plugin.system.customfieldtypes:textsearcher"
    [string] $select = "com.atlassian.jira.plugin.system.customfieldtypes:multiselectsearcher"
    [string] $textarea = "com.atlassian.jira.plugin.system.customfieldtypes:textsearcher"
    [string] $textfield = "com.atlassian.jira.plugin.system.customfieldtypes:textsearcher"
    [string] $url = "com.atlassian.jira.plugin.system.customfieldtypes:exacttextsearcher"
    [string] $userpicker = "com.atlassian.jira.plugin.system.customfieldtypes:userpickergroupsearcher"
    [string] $version = "com.atlassian.jira.plugin.system.customfieldtypes:versionsearcher"
}

class FieldOption {
    [string] $value
    [string] $optionId
    [boolean] $disabled

    FieldOption(
        [string] $value,
        [string] $optionId,
        [boolean] $disabled     
    ) {
        $this.value = $value
        $this.optionId = $optionId
        $this.disabled = $disabled
    }

    FieldOption(
        [string] $value,
        [boolean] $disabled     
    ) {
        $this.value = $value
        $this.disabled = $disabled
    }

    [string] to_json_body() {
        $fields = [ordered] @{
            value = $this.value
            disabled = $this.disabled
        }
        if ($this.optionId) {
            $fields["optionId"] = $this.optionId
        }
        return ($fields | ConvertTo-Json)
    }
}

class Field {
    [string] $name
    [string] $description
    [string] $type
    [string] $searcherKey

    Field(
        [string] $name,
        [string] $description,
        [string] $type,
        [string] $searcherKey
    ) {
        $this.name = $name
        $this.description = $description
        $this.type = $type
        $this.searcherKey = $searcherKey
    }

    [string] to_json_body() {
        $fields = [ordered] @{
            name = $this.name
            description = $this.description
            type = $this.type
            searcherKey = $this.searcherKey
        }
        return ($fields | ConvertTo-Json)
    }
}

class FieldContext {
    [string] $name
    [string] $description
    [string[]] $projectIds
    [string[]] $issueTypeIds
    
    FieldContext(
        [string] $name,
        [string] $description
    ) {
        $this.name = $name
        $this.description = $description
        $this.projectIds = @()
        $this.issueTypeIds = @("10039")
    }

    [string] to_json_body() {
        $fields = [ordered] @{
            name = $this.name
            description = $this.description
            projectIds = $this.projectIds
            issueTypeIds = $this.issueTypeIds
        }
        return ($fields | ConvertTo-Json)
    }
}

enum IssueType {
    Epic = 10000
    Story = 10001
    Task = 10002
    SubTask = 10003
    Bug = 10004
}

class Issue {
    [IssueType] $ty
    [string] $project_id
    [string] $parent_id 
    [string] $summary
    [string] $description
    [System.Collections.Hashtable] $additional_fields

    Issue(
        [IssueType] $ty,
        [string] $project_id,
        [string] $summary,
        [string] $description
    ) {
        if ($ty.Equals([IssueType]::SubTask)) {
            throw "Cannot create a `$($ty)` without a parent"
        }

        $this.ty = $ty 
        $this.project_id = $project_id
        $this.parent_id = $null
        $this.summary = $summary
        $this.description = $description
        $this.additional_fields = $null
    }

    Issue(
        [IssueType] $ty,
        [string] $project_id,
        [string] $summary,
        [string] $description,
        [System.Collections.Hashtable] $additional_fields
    ) {
        if ($ty.Equals([IssueType]::SubTask)) {
            throw "Cannot create a `$($ty)` without a parent"
        }

        $this.ty = $ty 
        $this.project_id = $project_id
        $this.parent_id = $null
        $this.summary = $summary
        $this.description = $description
        $this.additional_fields = $additional_fields
    }

    Issue(
        [IssueType] $ty,
        [string] $project_id,
        [string] $parent_id,
        [string] $summary,
        [string] $description
    ) {
        if (-Not $ty.Equals([IssueType]::SubTask)) {
            throw "Cannot create a `$($ty)` with a parent"
        }
 
        $this.ty = $ty 
        $this.project_id = $project_id
        $this.parent_id = $parent_id
        $this.summary = $summary
        $this.description = $description
        $this.additional_fields = $null
    }

    Issue(
        [IssueType] $ty,
        [string] $project_id,
        [string] $parent_id,
        [string] $summary,
        [string] $description,
        [System.Collections.Hashtable] $additional_fields
    ) {
        if (-Not $ty.Equals([IssueType]::SubTask)) {
            throw "Cannot create a `$($ty)` with a parent"
        }

        $this.ty = $ty 
        $this.project_id = $project_id
        $this.parent_id = $parent_id
        $this.summary = $summary
        $this.description = $description
        $this.additional_fields = $additional_fields
    }

    [string] to_json_body() {
        $fields = [ordered] @{
            project = @{
                key = $this.project_id
            }
            summary = $this.summary
            description = $this.description
            issuetype = @{
                name = $this.ty.ToString() 
            }
        }

        if ($this.parent_id) { 
            $fields["parent"] = @{
                id = $this.parent_id
            } 
        } 

        if ($this.additional_fields) {
            $this.additional_fields.GetEnumerator() | ForEach-Object {
                $fields[$_.key] = $_.value
            }
        }

        return (@{ fields = $fields } | ConvertTo-Json)
    }
}

class Project {
    [string] $name
    [string] $key
    [string] $project_type_key
    [string] $project_template_key
    [string] $description
    [string] $lead
    [string] $assignee_type
    [int] $avatar_id
}
