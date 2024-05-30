#!/usr/bin/env bash

_dhdev_completions()
{
  local cur level1 level2

  cur=${COMP_WORDS[COMP_CWORD]}
  level1=${COMP_WORDS[COMP_CWORD-1]}
  level2=${COMP_WORDS[COMP_CWORD-2]}

  #TODO Parse all the services directly from the docker-compose.yml files
  all_services="admin-tools
admin-tools-backend
davrods
davrods-upload
dh-home
elastic
epicpid
help-center
help-center-backend
icat
ires-hnas-azm
ires-hnas-um
irods-db
keycloak
ldap
mdr
mdr-db
mdr-home
minio1
minio2
sram-sync"

  case ${COMP_CWORD} in
    1)
      # Base-level completion: show subcommands
      COMPREPLY=($(compgen -W "make test stack up down build externals exec logs ps" -- ${cur}))
      ;;
    2)
      # Inner completion
      case ${level1} in
        make)
          # 'make' subcommand completion
          COMPREPLY=($(compgen -W "rules" -- ${cur}))
          ;;
        test)
          # 'test' subcommand completion
          COMPREPLY=($(compgen -W "irods mdr help-center-backend" -- ${cur}))
          ;;
        stack)
          # 'stack' subcommand completion
          COMPREPLY=($(compgen -W "minimal backend public frontend" -- ${cur}))
          ;;
        externals)
          # 'externals' subcommand completion
          COMPREPLY=($(compgen -W "checkout pull status" -- ${cur}))
          ;;
        build)
          # 'build' subcommand completion
          COMPREPLY=($(compgen -W "${all_services}" -- ${cur}))
          ;;
        up)
          # 'up' subcommand completion
          COMPREPLY=($(compgen -W "${all_services}" -- ${cur}))
          ;;
#        stop)
#          # 'stop' subcommand completion
#          actives_services=$(dhdev ps --services)
#          COMPREPLY=($(compgen -W "${actives_services}" -- ${cur}))
#          ;;
#        rm)
#          # 'rm' subcommand completion
#          actives_services=$(dhdev ps --services)
#          COMPREPLY=($(compgen -W "${actives_services}" -- ${cur}))
#          ;;
        exec)
          # 'exec' subcommand completion
          actives_services=$(dhdev ps --services)
          COMPREPLY=($(compgen -W "${actives_services}" -- ${cur}))
          ;;
        logs)
          # 'logs' subcommand completion
          actives_services=$(dhdev ps --services)
          COMPREPLY=($(compgen -W "${actives_services}" -- ${cur}))
          ;;
      esac
      ;;
    3)
      case ${level2} in
        up)
          case ${level1} in
            -d)
              # subcommand completion for: dhdev up -d
              COMPREPLY=($(compgen -W "${all_services}" -- ${cur}))
              ;;
          esac
          ;;
        logs)
          case ${level1} in
            -f)
              # subcommand completion for: dhdev logs -f
              actives_services=$(dhdev ps --services)
              COMPREPLY=($(compgen -W "${actives_services}" -- ${cur}))
              ;;
          esac
          ;;
        test)
          case ${level1} in
            irods)
              # subcommand completion for: dhdev test irods
              test_cases_list=$(cd  ./externals/irods-ruleset/test_cases && ls test_*.py)
              COMPREPLY=($(compgen -W "${test_cases_list}" -- ${cur}))
              ;;
#            mdr)
#              # subcommand completion for: dhdev test mdr
#              test_cases_list=$(cd  ./externals/dh-mdr/app/tests && ls test_*.py)
#              COMPREPLY=($(compgen -W "${test_cases_list}" -- ${cur}))
#              ;;
            help-center-backend)
              # subcommand completion for: dhdev test help-center-backend
              test_cases_list=$(cd  ./externals/dh-help-center/backend/tests/tests_confluence_documents && ls test_*.py)
              COMPREPLY=($(compgen -W "${test_cases_list}" -- ${cur}))
              ;;
          esac
          ;;
        stack)
          case ${level1} in
            minimal)
              # subcommand completion for: dhdev stack minimal
              COMPREPLY=($(compgen -W "build up down logs" -- ${cur}))
              ;;
            backend)
              # subcommand completion for: dhdev stack backend
              COMPREPLY=($(compgen -W "build up down logs" -- ${cur}))
              ;;
            public)
              # subcommand completion for: dhdev stack public
              COMPREPLY=($(compgen -W "build up down logs" -- ${cur}))
              ;;
          esac
          ;;
      esac
      ;;
    *)
      # All other cases: provide no completion
      COMPREPLY=()
      ;;
  esac
}
complete -F _dhdev_completions dhdev