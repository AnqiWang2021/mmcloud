#!/bin/bash

# mm_jobman.sh

# Help function
show_help() {
    echo "Usage: $0 [options] <script>"
    echo "Options:"
    echo "  -c <value>                   Number of CPUs (default: 2)"
    echo "  -m <value>                   Amount of memory (default: 16)"
    echo "  --mount <local>:<remote>     Mount local directory to remote (required)"
    echo "  --env [<key>=<val>]          Set environmental variables for the job (optional)"
    echo "  --download <local>:<remote>  Download from S3 (optional)"
    echo "  --upload <local>:<remote>    Upload to S3 (optional)"
    echo "  --image <value>              Docker image to use (required)"
    echo "  --mountOpt <value>           Mount options (required)"
    echo "  --opcenter <value>           Opcenter address (required)"
    echo "  --entrypoint '<command>'     Entrypoint command in the form of 'micromamba activate env' (required)"
    echo "  --job-size                   Divides the number of jobs to create VMs (default: 1)"
    echo "  --parallel-commands          Sets how many commands to run in parallel (default: 1)" 
    echo "  --dryrun                     If applied, will print all commands instead of running any."
    echo "  --cwd '<value>'              Specified working directory (default: /home/ec2-user)"
    echo "  --help                       Show this help message"
}


# Check if at least one argument is provided
if [ "$#" -eq 0 ]; then
    show_help
    exit 1
fi

# Initialize variables for options with default values
c_value=2
m_value=16
mountOpt=""
image=""
dryrun=false
declare -a mount_local=()
declare -a mount_remote=()
declare -a download_local=()
declare -a download_remote=()
declare -a upload_local=()
declare -a upload_remote=()
opcenter=""
entrypoint=""
cwd="/home/ec2-user"
env=""
job_size=1
parallel_commands=1

while (( "$#" )); do
  case "$1" in
    -c)
      c_value="$2"
      shift 2
      ;;
    -m)
      m_value="$2"
      shift 2
      ;;
    --mountOpt)
      mountOpt="$2"
      shift 2
      ;;
    --image)
      image="$2"
      shift 2
      ;;
    --mount|--download|--upload)
      current_flag="$1"
      shift
      while [ $# -gt 0 ] && [[ $1 != -* ]]; do
        IFS=':' read -ra PARTS <<< "$1"
        if [ "$current_flag" == "--mount" ]; then
          mount_local+=("${PARTS[0]}")
          mount_remote+=("${PARTS[1]}")
        elif [ "$current_flag" == "--download" ]; then
          download_local+=("${PARTS[0]}")
          download_remote+=("${PARTS[1]}")
        elif [ "$current_flag" == "--upload" ]; then
          upload_local+=("${PARTS[0]}")
          upload_remote+=("${PARTS[1]}")
        fi
        shift
      done
      ;;
    --opcenter)
      opcenter="$2"
      shift 2
      ;;
   --entrypoint)
      entrypoint="$2"
      shift 2
      ;;
   --cwd)
      cwd="$2"
      shift 2
      ;;
   --env)
      env="$2"
      shift 2
      ;;
   --job-size)
      job_size="$2"
      shift 2
      ;;
   --parallel-commands)
      parallel_commands="$2"
      shift 2
      ;;
   --dryrun)
      dryrun=true
      shift
      ;;
    --help)
      show_help
      exit 0
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *)
      SCRIPT_NAME="$1"  # Assume the first non-option argument is the script name
      shift
      ;;
  esac
done


check_required_params() {
    local missing_params=""
    local is_missing=false

    if [ -z "$image" ]; then
        missing_params+="--image, "
        is_missing=true
    fi
    if [ -z "$mountOpt" ]; then
        missing_params+="--mountOpt, "
        is_missing=true
    fi
    if [ -z "$opcenter" ]; then
        missing_params+="--opcenter, "
        is_missing=true
    fi
    if [ -z "$entrypoint" ]; then
        missing_params+="--entrypoint, "
        is_missing=true
    fi
    if [ ${#mount_local[@]} -eq 0 ]; then
        missing_params+="--mount, "
        is_missing=true
    fi

    # Remove trailing comma and space
    missing_params=${missing_params%, }

    if [ "$is_missing" = true ]; then
        echo "Error: Missing required parameters: $missing_params"
        show_help
        exit 1
    fi
}

create_download_commands() {
    local cmd=""
    for i in "${!download_local[@]}"; do
        local source="${download_remote[$i]}"
        local destination="${download_local[$i]}"

        # Add mkdir command
        cmd+="mkdir -p '$destination' && "

        # Add AWS download command
        cmd+="aws s3 sync 's3://$source' '$destination'"
        cmd+=" && "
    done

    # Remove the last ' && '
    cmd=${cmd% && }

    echo "$cmd"
}


create_upload_commands() {
    local cmd=""
    for i in "${!upload_local[@]}"; do
        local source="${upload_local[$i]}"
        local destination="${upload_remote[$i]}"

        # Add mkdir command for source folder if dne
        if [ ! -d "$source" ]; then
          cmd+="mkdir -p '$source' && "
        fi

        # Add AWS upload command
        cmd+="aws s3 sync '$source' 's3://$destination'"
        cmd+=" && "
    done

    # Remove the last ' && '
    cmd=${cmd% && }

    echo "$cmd"
}

generate_parallel_commands() {
  local job_commands=$1
  paralleled=""
  
  IFS=$'\n' read -d '' -ra array <<< "$(echo "$job_commands" | grep -o -E "'([^']+)'")"
  local start=0
  substring=""
  while [ $start -lt ${#array[@]} ]; do
      local end=$((start + parallel_commands))
      substring+="parallel ::: "
      for ((i = start; i < end && i < ${#array[@]}; i++)); do
          substring+="${array[i]} "
      done
      start=$end
      substring+=" && "
  done
  echo -e $substring
}

submit_each_line_with_mmfloat() {
    local script_file="$1"
    local download_cmd=""
    local upload_cmd=""
    local dataVolume_params=""

    # Only create download and upload commands if there are corresponding parameters
    if [ ${#download_local[@]} -ne 0 ]; then
        download_cmd=$(create_download_commands)
        download_cmd+=" && "
    fi
    if [ ${#upload_local[@]} -ne 0 ]; then
        upload_cmd=$(create_upload_commands)
	      upload_cmd=" && $upload_cmd"
    fi

    # Construct dataVolume parameters
    for i in "${!mount_local[@]}"; do
        dataVolume_params+="--dataVolume '[$mountOpt]:${mount_local[$i]}' "
    done


    # Check if the script file exists
    if [ ! -f "$script_file" ]; then
        echo "Script file does not exist: $script_file"
        return 1
    fi

    # Read all lines from the script file into an array
    all_commands=""
    total_commands=0
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue  # Skip empty lines
        fi
        all_commands+="'$line'\n"
        total_commands=$(( total_commands + 1))  
    done < "$script_file"
    all_commands=${all_commands%\\n}

    # Divide the commands into jobs based on job-size
    num_jobs=$(( ($total_commands + $job_size - 1) / $job_size )) # Ceiling division
    # Loop to create job submission commands
    for (( j = 1; j < $num_jobs + 1; j++ )); do
        full_cmd=""
        # Using a sliding-window effect, take the next job_size number of jobs
        start=$((($j - 1) * $job_size + 1))
        end=$(($start + $job_size - 1))
        job_commands=$(echo -e "$all_commands" | sed -n "$start,${end}p")

        # Extract commands to use with `parallel`
        paralleled=$(generate_parallel_commands "$job_commands")
        paralleled=${paralleled%&&}

        # Add the mmfloat submit command for each line
        if [ "$dryrun" = true ]; then
            full_cmd+="#-------------\n"
        fi
    
        # Set runner
        runner="#!/bin/bash\n"

        # Initialize shell for micromamba
        entrypoint_cmd="eval \"\$(micromamba shell hook --shell bash)\" && "
        # Activate environment with entrypoint in job script
        entrypoint_cmd+="$entrypoint && "

        # Remove entrypoint command from line
        subline=$(echo "$paralleled" | sed 's/--entrypoint "[^"]*"//g')

        # Replacing single quotes with double quotes
        # Because job script submitted removes single quotes
        subline=${subline//\'/\"}

        # cd into working directory in the job script
        cwd_cmd="cd '$cwd' && "

        # Comand to deactivate env
        deactivate_cmd=" && micromamba deactivate "

        # MMC job submission
        cmd="$runner$download_cmd$entrypoint_cmd$cwd_cmd$subline$deactivate_cmd$upload_cmd"
        full_cmd+="float submit -i '$image' -j <(echo -e '''$cmd''') -c '$c_value' -m '$m_value' $dataVolume_params --env '$env'\n"

        # Remove the last '\n'
        full_cmd=${full_cmd%\\n}
        # echo "------------------------"
        # echo -e $full_cmd

        # Execute or echo the full command
        if [ "$dryrun" = true ]; then
            echo -e "${full_cmd}"  # Replace '&&' with new lines for dry run
        else
            # TODO: Float login?
            eval "$full_cmd"
        fi
 
    done 
}

main() {
    check_required_params
    # Print some information to debug writting this script
    if [ "$dryrun" = true ]; then
        echo "#Processing script: $SCRIPT_NAME"
        echo "#c value: $c_value"
        echo "#m value: $m_value"
        echo "#mountOpt value: $mountOpt"
        echo "#image value: $image"
        echo "#opcenter value: $opcenter"
        echo "#entrypoint value: $entrypoint"
        echo "#cwd value: $cwd"
        echo "#env values: $env"
        echo "#job-size: $job_size"
        echo "#parallel-commands: $parallel_commands"
        echo "#commands to run:"
    fi
    # Call submit_each_line_with_mmfloat
    if [ -f "$SCRIPT_NAME" ]; then
        submit_each_line_with_mmfloat "$SCRIPT_NAME"
    else
        echo "Error: Script file not found: $SCRIPT_NAME"
        exit 1
    fi
}

main