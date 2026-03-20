# Bash completions for nsm (namespace manager)
# Source this file: . nsm-completions.bash
# Or install: cp nsm-completions.bash /etc/bash_completion.d/nsm

_nsm_completions() {
    local cur prev commands ns_types
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="list inspect create enter exec diff tree destroy ps monitor help"
    ns_types="net uts pid mnt ipc user cgroup all"

    case "$prev" in
        nsm)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            return 0
            ;;
        --type|-t)
            COMPREPLY=( $(compgen -W "$ns_types" -- "$cur") )
            return 0
            ;;
        --ns-type)
            COMPREPLY=( $(compgen -W "$ns_types" -- "$cur") )
            return 0
            ;;
        enter|destroy|exec|inspect)
            # Complete with existing namespace names
            local names=""
            if [[ -d /run/nsm ]]; then
                names=$(ls /run/nsm/ 2>/dev/null)
            fi
            COMPREPLY=( $(compgen -W "$names" -- "$cur") )
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
}

complete -F _nsm_completions nsm
