#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------
# DEBUG SWITCH (set to true to enable)
DEBUG=true
# --------------------------------------

# Parameters
ChangesFilePath=$1
BuildNumber=$2
TcProjectName=$3
CuApiKey=$4
BranchName=$5
TeamcityUrl=$6
TcApiKey=$7
BuildTypeId=$8

releasePrefix="3.0."

cuIdRegex='CU-([A-Za-z0-9]+)'

# REST API URLs
tcHeaders=(-H "Authorization: Bearer $TcApiKey" -H "Accept: application/json")
tcGetBuildsUrl="${TeamcityUrl}/app/rest/builds?locator=buildType:${BuildTypeId},branch:${BranchName},state:finished,count:20&fields=build(id,number,status)"
tcGetChangesUrl="${TeamcityUrl}/app/rest/changes?locator=build:(id:%s)&fields=change(version)"

getTaskHeaders=(-H "Authorization: $CuApiKey" -H "Accept: application/json")
postFieldHeaders=(-H "Authorization: $CuApiKey" -H "Accept: application/json" -H "Content-Type: application/json")
getTaskUrl="https://api.clickup.com/api/v2/task/%s"
postFieldUrl="https://api.clickup.com/api/v2/task/%s/field/%s"

# Project mapping
declare -A projectNameMap=(
  ["Emplo"]="TMS"
  ["Admin2"]="Admin"
  ["Build Wallapi Docker"]="Wall"
)

read_nonempty_array() {
  local __name=$1
  shift
  local line arr=()
  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] && arr+=("$line")
  done
  eval "$__name=(\"\${arr[@]}\")"
}


get_mapped_project_name() {
  local name="$1"
  if [[ -n "${projectNameMap[$name]:-}" ]]; then
    echo "Using '${projectNameMap[$name]}' as project name" >&2
    echo "${projectNameMap[$name]}"
  else
    echo "Warning: No mapping for project '$name'" >&2
    echo "$name"
  fi
}

get_previous_builds_revs() {
  local json buildId status revs=()
  json=$(curl -s "${tcHeaders[@]}" "$tcGetBuildsUrl")
  
  [[ "$DEBUG" == true ]] && echo "# DEBUG: Sent GET $tcGetBuildsUrl" >&2
  [[ "$DEBUG" == true ]] && echo "# DEBUG: Received: $json" >&2

  # parse each id/number/status triplet, break on SUCCESS
  echo "$json" \
    | grep -Eo '"id":[0-9]+|"number":"[^"]+"|"status":"[^"]+"' \
    | paste - - - \
    | while IFS=$'\t' read -r idLine numberLine statusLine; do
  	    buildId=${idLine//[^0-9]/}
  	    buildNumber=${numberLine#*\"number\":\"}
  	    buildNumber=${buildNumber%\"}
  	    status=${statusLine#*\"status\":\"}
  	    status=${status%\"}
	    
  	    if [[ $status == "SUCCESS" ]]; then
  		  break
  	    fi
  	    echo "Found failed build: $buildNumber" >&2
	    
  	    # pull all change versions
  	    url="$(printf "$tcGetChangesUrl" "$buildId")"
  	    [[ "$DEBUG" == true ]] && echo "# DEBUG: Sent GET $url" >&2
  	    local changesJson=$(curl -s "${tcHeaders[@]}" "$url")
  	    [[ "$DEBUG" == true ]] && echo "# DEBUG: Received: $changesJson" >&2
        
		ho "$changesJson" \
          | grep -oP '"version":"\K[^"]+' \
          || true
      done \
        | sort -u
}

get_current_build_revs() {
  awk -F: '{print $NF}' "$ChangesFilePath" | sort -u
}

get_task_ids_from_revs() {
  local rev cuIds=() msg match
  for rev in "$@"; do
    [[ -z "$rev" ]] && continue
    msg=$(git log -1 --format="%s" "$rev" 2>/dev/null || true)
    while [[ "$msg" =~ $cuIdRegex ]]; do
      cuIds+=("${BASH_REMATCH[1]}")
      msg=${msg#*"${BASH_REMATCH[0]}"}
    done
  done
  printf '%s\n' "${cuIds[@]}" | sort -u
}

update_clickup_tasks() {
  local projectName="$1"; shift
  local projectReleaseValue releaseValue fieldId
  projectReleaseValue="${projectName} - ${releasePrefix}${BuildNumber}"

  for taskId in "$@"; do
    url="$(printf "$getTaskUrl" "$taskId")"
    [[ "$DEBUG" == true ]] && echo "# DEBUG: Sent GET $url" >&2
    resp=$(curl -s "${getTaskHeaders[@]}" "$url")
    [[ "$DEBUG" == true ]] && echo "# DEBUG: Received: $resp" >&2

    # Extract fieldId and current value manually without jq
	fieldId=$(echo "$resp" \
	  | grep -oP '"name":"Release".*?"id":"\K[^"]+' || true)
    [[ "$DEBUG" == true ]] && echo "# DEBUG: Release field id: $fieldId" >&2
	
	releaseValue=$(echo "$resp" \
	  | grep -oP '"name":"Release".*?"value":"\K[^"]*' || true)
	  
	# Project present with build number
    if [[ "$releaseValue" =~ $projectWithBuildRegex ]]; then
      releaseValue=$(echo "$releaseValue" | sed -E "s/$projectWithBuildRegex/$projectReleaseValue/I")
	# Project present without build number
    elif [[ "$releaseValue" =~ $projectWordRegex ]]; then
      releaseValue=$(echo "$releaseValue" | sed -E "s/$projectWordRegex/$projectReleaseValue/I")
	# Field is empty
    elif [[ -z "$releaseValue" ]]; then
      releaseValue="$projectReleaseValue"
	# Field contains text
    else
      releaseValue="${projectReleaseValue}, $releaseValue"
    fi

    echo "[$taskId] changing Release field to: '$releaseValue'"

    # --- Do not update during testing ---
    # curl -s -X POST "${postFieldHeaders[@]}" \
    #     -d "{\"value\":\"${releaseValue}\"}" \
    #     "$(printf "$postFieldUrl" "$taskId" "$fieldId")" >/dev/null && \
    #     echo "[$taskId] Successfully updated Release to '$releaseValue'" || \
    #     echo "[$taskId] Warning: Failed to update Release field" >&2
    # -------------------------------------
  done
}

# Main Execution
projectName=$(get_mapped_project_name "$TcProjectName")

projectWordRegex="\\b${projectName}\\b"
projectWithBuildRegex="\\b${projectName}\\b[-[:space:]]*[0-9]+(\\.[0-9A-Za-z.-]*)?"

read_nonempty_array previousRevs < <(get_previous_builds_revs)
[[ "$DEBUG" == true ]] && (( ${#previousRevs[@]} )) && echo "# DEBUG: Previous builds revs:" >&2 && printf ' - %s\n' "${previousRevs[@]}" >&2
read_nonempty_array previousCuIds < <(get_task_ids_from_revs "${previousRevs[@]}")
[[ "$DEBUG" == true ]] && (( ${#previousCuIds[@]} )) && echo "# DEBUG: Previous builds tasks:" >&2 && printf ' - %s\n' "${previousCuIds[@]}" >&2

if (( ${#previousCuIds[@]} )); then
  echo "Found ${#previousCuIds[@]} tasks from failed builds"
  printf ' - %s\n' "${previousCuIds[@]}"
fi

read_nonempty_array currentRevs < <(get_current_build_revs)
[[ "$DEBUG" == true ]] && (( ${#currentRevs[@]} )) && echo "# DEBUG: Current build revs:" >&2 && printf ' - %s\n' "${currentRevs[@]}" >&2
read_nonempty_array currentCuIds < <(get_task_ids_from_revs "${currentRevs[@]}")
[[ "$DEBUG" == true ]] && (( ${#currentCuIds[@]} )) && echo "# DEBUG: Current build tasks:" >&2 && printf ' - %s\n' "${currentCuIds[@]}" >&2

if (( ${#currentCuIds[@]} )); then
  echo "Found ${#currentCuIds[@]} CU tasks:"
  printf ' - %s\n' "${currentCuIds[@]}"
fi

read_nonempty_array allCuIds < <(printf '%s\n' "${previousCuIds[@]}" "${currentCuIds[@]}" | sort -u)

if (( ${#allCuIds[@]} == 0 )); then
  echo "No CU tasks found. Exiting."
  exit 0
fi

update_clickup_tasks "$projectName" "${allCuIds[@]}"
