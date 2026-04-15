#!/bin/bash
set -e

# Help function
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --expected-repo=http://github.com/my-repo    The repo URL that is expected to be set"
  echo "  --expected-branch=main    The branch that is expected to be set"
  echo "  --github    Report error messages using the GitHub Actions annotation format."
  echo "  --debug     Print additional debug information."
  echo "  --help                Show this help message"
}

for arg in "$@"
do
  case $arg in
    --expected-repo=*)
    export EXPECTED_REPO="${arg#*=}"
    shift
    ;;
    --expected-branch=*)
    export EXPECTED_BRANCH"${arg#*=}"
    shift
    ;;
    --github)
    export GITHUB=true
    shift
    ;;
    --debug)
    export DEBUG=true
    shift
    ;;
    --help)
    show_help
    exit 0
    ;;
  esac
done

EXPECTED_REPO=${EXPECTED_REPO:-"https://github.com/redhat-ai-services/ai-accelerator.git"}
EXPECTED_BRANCH=${EXPECTED_BRANCH:-"main"}

DEBUG=${DEBUG:-false}
GITHUB=${GITHUB:-false}

ERROR_DETECTED=false


get_cluster_branch() {
  if [ -z "$1" ]; then
    echo "No patch file supplied."
    exit 1
  else
    PATCH_FILE=$1
  fi

  if [ -z "$2" ]; then
    RETURN_LINE_NUMBER=false
  else
    RETURN_LINE_NUMBER=$2
  fi

  APP_PATCH_PATH=".spec.source.targetRevision"

  if ${RETURN_LINE_NUMBER}; then
    query="${APP_PATCH_PATH} | line"
  else
    query="${APP_PATCH_PATH}"
  fi

  VALUE=$(yq -r "${query}" ${PATCH_FILE})

  echo ${VALUE}
}

get_cluster_repo() {
  if [ -z "$1" ]; then
    echo "No patch file supplied."
    exit 1
  else
    PATCH_FILE=$1
  fi

  if [ -z "$2" ]; then
    RETURN_LINE_NUMBER=false
  else
    RETURN_LINE_NUMBER=$2
  fi

  APP_PATCH_PATH=".spec.source.repoURL"

  if ${RETURN_LINE_NUMBER}; then
    query="${APP_PATCH_PATH} | line"
  else
    query="${APP_PATCH_PATH}"
  fi

  VALUE=$(yq -r "${query}" ${PATCH_FILE})

  echo ${VALUE}
}

verify_branch() {
  if [ -z "$1" ]; then
    echo "No patch file supplied."
    exit 1
  else
    PATCH_FILE=$1
  fi

  if [ -z "$2" ]; then
    echo "No expected branch supplied."
    exit 1
  else
    EXPECTED_BRANCH=$2
  fi

  if ${DEBUG}; then
    echo "Verifying if ${PATCH_FILE} is set to ${EXPECTED_BRANCH}"
  fi

  CLUSTER_BRANCH=$(get_cluster_branch ${PATCH_FILE})

  if [[ "${CLUSTER_BRANCH}" != "${EXPECTED_BRANCH}" ]]; then

    if ${GITHUB}; then
      line_number=$(get_cluster_branch ${PATCH_FILE} true)
            message="Expected \`${EXPECTED_BRANCH}\` but got \`${CLUSTER_BRANCH}\`"
      echo "::error file=${PATCH_FILE},line=${line_number},col=10,title=Incorrect Branch::${message}"
    else
            echo "Expected ${PATCH_FILE} to be set to \`${EXPECTED_BRANCH}\` but got \`${CLUSTER_BRANCH}\`"
    fi

    ERROR_DETECTED=true
  fi
}

verify_repo() {
  if [ -z "$1" ]; then
    echo "No patch file supplied."
    exit 1
  else
    PATCH_FILE=$1
  fi

  if [ -z "$2" ]; then
    echo "No expected repo supplied."
    exit 1
  else
    EXPECTED_REPO=$2
  fi

  if ${DEBUG}; then
    echo "Verifying if ${PATCH_FILE} is set to ${EXPECTED_REPO}"
  fi

  CLUSTER_REPO=$(get_cluster_repo ${PATCH_FILE})

  if [[ "${CLUSTER_REPO}" != "${EXPECTED_REPO}" ]]; then

    if ${GITHUB}; then
      line_number=$(get_cluster_repo ${PATCH_FILE} true)
            message="Expected \`${EXPECTED_REPO}\` but got \`${CLUSTER_REPO}\`"
      echo "::error file=${PATCH_FILE},line=${line_number},col=10,title=Incorrect Repo URL::${message}"
    else
            echo "Expected ${PATCH_FILE} to be set to \`${EXPECTED_REPO}\` but got \`${CLUSTER_REPO}\`"
    fi

    ERROR_DETECTED=true
  fi
}

verify_configmap_repo() {
  if [ -z "$1" ]; then
    echo "No kustomization file supplied."
    exit 1
  else
    KUST_FILE=$1
  fi

  if [ -z "$2" ]; then
    echo "No expected repo supplied."
    exit 1
  else
    EXPECTED_REPO=$2
  fi

  if ${DEBUG}; then
    echo "Verifying if ${KUST_FILE} configMapGenerator is set to ${EXPECTED_REPO}"
  fi

  # Extract repoURL from configMapGenerator
  CONFIGMAP_REPO=$(yq -r '.configMapGenerator[] | select(.name == "gitops-repo-config") | .literals[]' ${KUST_FILE} | grep "^repoURL=" | cut -d= -f2)

  if [[ -z "${CONFIGMAP_REPO}" ]]; then
    if ${DEBUG}; then
      echo "Skipping ${KUST_FILE} - no configMapGenerator found"
    fi
    return 0
  fi

  if [[ "${CONFIGMAP_REPO}" != "${EXPECTED_REPO}" ]]; then
    if ${GITHUB}; then
      line_number=$(yq '.configMapGenerator[] | select(.name == "gitops-repo-config") | .literals[] | select(. | contains("repoURL")) | line' ${KUST_FILE})
      message="Expected \`${EXPECTED_REPO}\` but got \`${CONFIGMAP_REPO}\`"
      echo "::error file=${KUST_FILE},line=${line_number},col=10,title=Incorrect Repo URL in ConfigMap::${message}"
    else
      echo "Expected ${KUST_FILE} configMapGenerator to be set to \`${EXPECTED_REPO}\` but got \`${CONFIGMAP_REPO}\`"
    fi

    ERROR_DETECTED=true
  fi
}

verify_configmap_branch() {
  if [ -z "$1" ]; then
    echo "No kustomization file supplied."
    exit 1
  else
    KUST_FILE=$1
  fi

  if [ -z "$2" ]; then
    echo "No expected branch supplied."
    exit 1
  else
    EXPECTED_BRANCH=$2
  fi

  if ${DEBUG}; then
    echo "Verifying if ${KUST_FILE} configMapGenerator is set to ${EXPECTED_BRANCH}"
  fi

  # Extract targetRevision from configMapGenerator
  CONFIGMAP_BRANCH=$(yq -r '.configMapGenerator[] | select(.name == "gitops-repo-config") | .literals[]' ${KUST_FILE} | grep "^targetRevision=" | cut -d= -f2)

  if [[ -z "${CONFIGMAP_BRANCH}" ]]; then
    if ${DEBUG}; then
      echo "Skipping ${KUST_FILE} - no configMapGenerator found"
    fi
    return 0
  fi

  if [[ "${CONFIGMAP_BRANCH}" != "${EXPECTED_BRANCH}" ]]; then
    if ${GITHUB}; then
      line_number=$(yq '.configMapGenerator[] | select(.name == "gitops-repo-config") | .literals[] | select(. | contains("targetRevision")) | line' ${KUST_FILE})
      message="Expected \`${EXPECTED_BRANCH}\` but got \`${CONFIGMAP_BRANCH}\`"
      echo "::error file=${KUST_FILE},line=${line_number},col=10,title=Incorrect Branch in ConfigMap::${message}"
    else
      echo "Expected ${KUST_FILE} configMapGenerator to be set to \`${EXPECTED_BRANCH}\` but got \`${CONFIGMAP_BRANCH}\`"
    fi

    ERROR_DETECTED=true
  fi
}

main() {
  APP_PATCH_FILE="./components/argocd/apps/base/cluster-config-app-of-apps.yaml"
  APP_PATCH_PATH=".spec.source.targetRevision"

  # Validate base Application file
  verify_branch "${APP_PATCH_FILE}" ${EXPECTED_BRANCH}
  verify_repo "${APP_PATCH_FILE}" ${EXPECTED_REPO}

  # Validate all cluster overlay ConfigMap generators
  for overlay in clusters/overlays/*/kustomization.yaml; do
    if [ -f "$overlay" ]; then
      verify_configmap_branch "$overlay" ${EXPECTED_BRANCH}
      verify_configmap_repo "$overlay" ${EXPECTED_REPO}
    fi
  done

  if ${ERROR_DETECTED}; then
    exit 1
  fi
}

main
