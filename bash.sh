#!/usr/bin/env bash
set -euo pipefail

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

# Regex
cuIdRegex='CU-([A-Za-z0-9]+)'
projectWordRegex="\\b%s\\b"
projectWithBuildRegex="\\b%s\\b[[:space:]]*(?:[:\\-][[:space:]]*|[[:space:]]+)[0-9A-Za-z.\\-]*"

# REST API URLs
tcHeaders=(-H "Authorization: Bearer $TcApiKey")
tcGetBuildsUrl="${TeamcityUrl}/app/rest/builds?locator=buildType:${BuildTypeId},branch:${BranchName},state:finished,count:20&fields=build(id,status)"
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
  local builds json buildId status revs=()
  json=$(curl -s "${tcHeaders[@]}" "$tcGetBuildsUrl")

  echo "$json" | grep -Eo '"id":[0-9]+|"status":"[^"]+"' | paste - - |
  while IFS=$'\t' read -r idLine statusLine; do
    buildId=${idLine//[^0-9]/}
    status=${statusLine//\"status\":\"/}
    status=${status%\"}
    if [[ $status == "SUCCESS" ]]; then break; fi
    echo "Found failed build: $buildId" >&2

    changesJson=$(curl -s "${tcHeaders[@]}" "$(printf "$tcGetChangesUrl" "$buildId")")
    echo "$changesJson" | grep -oE '"version":"[^"]+"' | cut -d'"' -f4
  done | sort -u
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
  local re_word re_withnum projectReleaseValue releaseValue fieldId
  projectReleaseValue="${projectName} - ${releasePrefix}${BuildNumber}"
  re_word=$(printf "$projectWordRegex" "$projectName")
  re_withnum=$(printf "$projectWithBuildRegex" "$projectName")

  for taskId in "$@"; do
    echo "Processing task $taskId..." >&2
    resp=$(curl -s "${getTaskHeaders[@]}" "$(printf "$getTaskUrl" "$taskId")")

    # Extract fieldId and current value manually without jq
    fieldId=$(echo "$resp" | grep -A10 '"name":"Release"' | grep '"id":' | head -n1 | sed -E 's/.*"id":"([^"]+)".*/\1/')
    releaseValue=$(echo "$resp" | grep -A10 '"name":"Release"' | grep '"value":' | head -n1 | sed -E 's/.*"value":"?([^"]*)"?[,]?/\1/')

    if [[ "$releaseValue" =~ $re_withnum ]]; then
      releaseValue=$(echo "$releaseValue" | sed -E "s/$re_withnum/$projectReleaseValue/I")
      echo "[$taskId] Updated existing project+build."
    elif [[ "$releaseValue" =~ $re_word ]]; then
      releaseValue=$(echo "$releaseValue" | sed -E "s/$re_word/$projectReleaseValue/I")
      echo "[$taskId] Added build number to existing project."
    elif [[ -z "$releaseValue" ]]; then
      releaseValue="$projectReleaseValue"
      echo "[$taskId] Set new Release field."
    else
      releaseValue="${projectReleaseValue}, $releaseValue"
      echo "[$taskId] Prepended new release value."
    fi

    echo "[$taskId] Final Release value: '$releaseValue'" >&2

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

mapfile -t previousRevs < <(get_previous_builds_revs)
mapfile -t previousCuIds < <(get_task_ids_from_revs "${previousRevs[@]}")

if (( ${#previousCuIds[@]} )); then
  echo "Warning: ${#previousCuIds[@]} tasks from failed builds" >&2
  printf ' - %s\n' "${previousCuIds[@]}" >&2
fi

mapfile -t currentRevs < <(get_current_build_revs)
mapfile -t currentCuIds < <(get_task_ids_from_revs "${currentRevs[@]}")

if (( ${#currentCuIds[@]} )); then
  echo "Found ${#currentCuIds[@]} CU tasks:"
  printf ' - %s\n' "${currentCuIds[@]}"
fi

mapfile -t allCuIds < <(printf '%s\n' "${previousCuIds[@]}" "${currentCuIds[@]}" | sort -u)

if (( ${#allCuIds[@]} == 0 )); then
  echo "No CU tasks found. Exiting." >&2
  exit 0
fi

update_clickup_tasks "$projectName" "${allCuIds[@]}"
