#!/usr/bin/env bash
set -euo pipefail

# --- Parameters (positional) ---
# $1 = ChangesFilePath
# $2 = BuildNumber
# $3 = TcProjectName
# $4 = CuApiKey
# $5 = BranchName
# $6 = TeamcityUrl
# $7 = TcApiKey
# $8 = BuildTypeId
ChangesFilePath=$1
BuildNumber=$2
TcProjectName=$3
CuApiKey=$4
BranchName=$5
TeamcityUrl=$6
TcApiKey=$7
BuildTypeId=$8

# --- Constants & Regex ---
releasePrefix="3.0."
cuIdRegex='(?i)CU-([A-Za-z0-9]+)'
projectWordRegex="\\b%s\\b"
projectWithBuildRegex="\\b%s\\b\\s*(?:[:\\-]\\s*|\\s+)[0-9][A-Za-z0-9.\\-]*"

# --- TeamCity REST endpoints ---
tcHeaders=(-H "Authorization: Bearer ${TcApiKey}")
tcGetBuildsUrl="${TeamcityUrl}/app/rest/builds?locator=buildType:${BuildTypeId},branch:${BranchName},state:finished,count:20&fields=build(id,status)"
tcGetChangesUrl="${TeamcityUrl}/app/rest/changes?locator=build:(id:%s)&fields=change(version)"

# --- ClickUp REST endpoints ---
getTaskHeaders=(-H "Authorization: ${CuApiKey}" -H "Accept: application/json")
postFieldHeaders=(-H "Authorization: ${CuApiKey}" -H "Accept: application/json" -H "Content-Type: application/json")
getTaskUrl="https://api.clickup.com/api/v2/task/%s"
postFieldUrl="https://api.clickup.com/api/v2/task/%s/field/%s"

# --- Project name map & lookup ---
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
    echo "Warning: Couldn't find '${name}' in project name map" >&2
    echo "$name"
  fi
}

get_previous_builds_revs() {
  local lines buildId status revs=() newrev
  mapfile -t lines < <(curl -s "${tcHeaders[@]}" "$tcGetBuildsUrl" \
    | jq -r '.build[] | "\(.id)\t\(.status)"')
  for line in "${lines[@]}"; do
    buildId=${line%%$'\t'*}
    status=${line##*$'\t'}
    if [[ "$status" == "SUCCESS" ]]; then
      break
    fi
    echo "Found failed build: $buildId" >&2
    mapfile -t newrev < <(curl -s "${tcHeaders[@]}" \
      "$(printf "$tcGetChangesUrl" "$buildId")" \
      | jq -r '.changes.change[].version')
    revs+=("${newrev[@]}")
  done
  printf '%s\n' "${revs[@]}" | sort -u
}

get_current_build_revs() {
  awk -F: '{print $NF}' "$ChangesFilePath" | sort -u
}

get_task_ids_from_revs() {
  local rev msg cuIds=() match
  for rev in "$@"; do
    [[ -z "$rev" ]] && continue
    msg=$(git log -1 --format="%s" "$rev")
    while [[ $msg =~ $cuIdRegex ]]; do
      match=${BASH_REMATCH[1]}
      cuIds+=("$match")
      msg=${msg#*${BASH_REMATCH[0]}}
    done
  done
  printf '%s\n' "${cuIds[@]}" | sort -u
}

update_clickup_tasks() {
  local projectName="$1"; shift
  local re_word re_withnum projectReleaseValue
  re_word=$(printf "$projectWordRegex" "$projectName")
  re_withnum=$(printf "$projectWithBuildRegex" "$projectName")
  projectReleaseValue="${projectName} - ${releasePrefix}${BuildNumber}"

  for taskId in "$@"; do
    echo "Processing task $taskId..."  # stdout
    local resp fieldId releaseValue

    resp=$(curl -s "${getTaskHeaders[@]}" \
      "$(printf "$getTaskUrl" "$taskId")")

    fieldId=$(jq -r --arg name "Release" '.custom_fields[]
      | select(.name==$name).id' <<<"$resp")
    releaseValue=$(jq -r --arg name "Release" '.custom_fields[]
      | select(.name==$name).value // ""' <<<"$resp")

    if [[ "$releaseValue" =~ $re_withnum ]]; then
      releaseValue=$(echo "$releaseValue" | sed -E \
        "s/$re_withnum/$projectReleaseValue/I")
      echo "[$taskId] Replaced existing project+build."
    elif [[ "$releaseValue" =~ $re_word ]]; then
      releaseValue=$(echo "$releaseValue" | sed -E \
        "s/$re_word/$projectReleaseValue/I")
      echo "[$taskId] Added build number to existing project."
    elif [[ -z "${releaseValue// /}" ]]; then
      releaseValue="$projectReleaseValue"
      echo "[$taskId] Setting new Release value."
    else
      releaseValue="${projectReleaseValue}, ${releaseValue}"
      echo "[$taskId] Prepending to existing text."
    fi

    if curl -s -X POST "${postFieldHeaders[@]}" \
        -d "{\"value\":\"${releaseValue}\"}" \
        "$(printf "$postFieldUrl" "$taskId" "$fieldId")" >/dev/null; then
      echo "[$taskId] Successfully updated Release to '$releaseValue'."
    else
      echo "[$taskId] Warning: Failed to update Release field." >&2
    fi
  done
}

# --- Main ---
projectName=$(get_mapped_project_name "$TcProjectName")

mapfile -t previousRevs < <(get_previous_builds_revs)
previousCuIds=($(get_task_ids_from_revs "${previousRevs[@]}"))

if (( ${#previousCuIds[@]} )); then
  echo "Warning: Found ${#previousCuIds[@]} tasks in previous failed builds." >&2
  printf 'Previous builds tasks:\n' >&2
  printf ' - %s\n' "${previousCuIds[@]}" >&2
fi

mapfile -t currentRevs < <(get_current_build_revs)
currentCuIds=($(get_task_ids_from_revs "${currentRevs[@]}"))

if (( ${#currentCuIds[@]} )); then
  echo "Found new ${#currentCuIds[@]} CU tasks:"
  printf ' - %s\n' "${currentCuIds[@]}"
fi

allCuIds=($(printf '%s\n' "${previousCuIds[@]}" "${currentCuIds[@]}" | sort -u))
if (( ${#allCuIds[@]} == 0 )); then
  echo "Warning: No CU tasks found; nothing to update." >&2
  exit 0
fi

update_clickup_tasks "$projectName" "${allCuIds[@]}"
