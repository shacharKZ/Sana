#!/bin/bash
export LOGLEVEL=INFO
output_dir=output

#### Infer Hyper
default_step=20                             # inference step for diffusion model
# default_bs=50                                # batch size for inference
default_bs=8                                # batch size for inference
# default_sample_nums=30000                   # inference first $sample_nums sample in list(json.keys())
default_sample_nums=1024                   # inference first $sample_nums sample in list(json.keys())
default_sampling_algo="dpm-solver"
default_json_file="data/test/PG-eval-data/MJHQ-30K/meta_data.json"   # MJHQ-30K meta json
default_add_label=''

#### Metrics Hyper
# default_img_size=512  # 1024                        # img size for fid reference embedding
default_img_size=1024  # 1024                        # img size for fid reference embedding
default_fid_suffix_label=''                         # suffix of the line chart on wandb
default_log_fid=false    #false
default_log_clip_score=false
default_log_image_reward=false
default_log_dpg=false

# 👇No need to change the code below
if [ -n "$1" ]; then
  config_file=$1
fi

if [ -n "$2" ]; then
  model_paths_file=$2
fi

for arg in "$@"
do
    case $arg in
        --np=*)
        np="${arg#*=}"
        shift
        ;;
        --step=*)
        step="${arg#*=}"
        shift
        ;;
        --bs=*)
        bs="${arg#*=}"
        shift
        ;;
        --sample_nums=*)
        sample_nums="${arg#*=}"
        shift
        ;;
        --sampling_algo=*)
        sampling_algo="${arg#*=}"
        shift
        ;;
        --json_file=*)
        json_file="${arg#*=}"
        shift
        ;;
        --exist_time_prefix=*)
        exist_time_prefix="${arg#*=}"
        shift
        ;;
        --img_size=*)
        img_size="${arg#*=}"
        shift
        ;;
        --dataset=*)
        dataset="${arg#*=}"
        shift
        ;;
        --cfg_scale=*)
        cfg_scale="${arg#*=}"
        shift
        ;;
        --fid_suffix_label=*)
        fid_suffix_label="${arg#*=}"
        shift
        ;;
        --add_label=*)
        add_label="${arg#*=}"
        shift
        ;;
        --log_fid=*)
        log_fid="${arg#*=}"
        shift
        ;;
        --log_clip_score=*)
        log_clip_score="${arg#*=}"
        shift
        ;;
        --log_image_reward=*)
        log_image_reward="${arg#*=}"
        shift
        ;;
        --log_dpg=*)
        log_dpg="${arg#*=}"
        shift
        ;;
        --inference=*)
        inference="${arg#*=}"
        shift
        ;;
        --fid=*)
        fid="${arg#*=}"
        shift
        ;;
        --clipscore=*)
        clipscore="${arg#*=}"
        shift
        ;;
        --imagereward=*)
        imagereward="${arg#*=}"
        shift
        ;;
        --dpg=*)
        dpg="${arg#*=}"
        shift
        ;;
        --output_dir=*)
        output_dir="${arg#*=}"
        shift
        ;;
        --auto_ckpt=*)
        auto_ckpt="${arg#*=}"
        shift
        ;;
        --auto_ckpt_interval=*)
        auto_ckpt_interval="${arg#*=}"
        shift
        ;;
        --tracker_pattern=*)
        tracker_pattern="${arg#*=}"
        shift
        ;;
        --tracker_project_name=*)
        tracker_project_name="${arg#*=}"
        shift
        ;;
        --ablation_key=*)
        ablation_key="${arg#*=}"
        shift
        ;;
        --ablation_selections=*)
        ablation_selections="${arg#*=}"
        shift
        ;;
        --inference_script=*)
        inference_script="${arg#*=}"
        shift
        ;;
        --cleanup=*)
        cleanup="${arg#*=}"
        shift
        ;;
        --stich_config=*)
        stich_config="${arg#*=}"
        shift
        ;;
        *)
        ;;
    esac
done

inference=${inference:-true}
fid=${fid:-true}
clipscore=${clipscore:-true}
imagereward=${imagereward:-false}
dpg=${dpg:-false}

# np=${np:-8}
np=${np:-1}
step=${step:-$default_step}
bs=${bs:-$default_bs}
dataset=${dataset:-'custom'}
cfg_scale=${cfg_scale:-4.5}
sample_nums=${sample_nums:-$default_sample_nums}
sampling_algo=${sampling_algo:-$default_sampling_algo}
json_file=${json_file:-$default_json_file}
exist_time_prefix=${exist_time_prefix:-$default_exist_time_prefix}
add_label=${add_label:-$default_add_label}
ablation_key=${ablation_key:-''}
ablation_selections=${ablation_selections:-''}

img_size=${img_size:-$default_img_size}
fid_suffix_label=${fid_suffix_label:-$default_fid_suffix_label}
tracker_pattern=${tracker_pattern:-"epoch_step"}
tracker_project_name=${tracker_project_name:-"sana-baseline"}
log_fid=${log_fid:-$default_log_fid}
log_clip_score=${log_clip_score:-$default_log_clip_score}
log_image_reward=${log_image_reward:-$default_log_image_reward}
log_dpg=${log_dpg:-$default_log_dpg}
auto_ckpt=${auto_ckpt:-false}
auto_ckpt_interval=${auto_ckpt_interval:-0}
cleanup=${cleanup:-false}

stich_config=${stich_config:-''}

echo "Metrics suffix label: $fid_suffix_label"

echo "The given stich parameter is:"
echo "$stich_config"

job_name=$(basename $(dirname $(dirname "$model_paths_file")))
job_name="${job_name}__${sampling_algo}"
if [ -n "$stich_config" ]; then
    # echo "BP1"
    echo "$stich_config"
    # Extract the last part of the string after the last "/"
    last_part="${stich_config##*/}"
    # If the last segment contains a dot, remove the suffix starting from the last dot
    if [[ "$last_part" == *.* ]]; then
        last_part="${last_part%.*}"
    fi
    # Append the last part to my_param
    job_name="${job_name}__${last_part}"
    echo "stich is going on"
    echo "$job_name"
fi

work_dir=$output_dir/$job_name
echo "work dir: ${work_dir}"

metric_dir=$work_dir/metrics
echo "metrics dir: ${metric_dir}"
if [ ! -d "$metric_dir" ]; then
  echo "Creating directory: $metric_dir"
  mkdir -p "$metric_dir"
fi

# # select all the last step ckpts of one epoch to inference
# if [ "$auto_ckpt" = true ]; then
#   bash scripts/collect_pth_path.sh $output_dir/$job_name/checkpoints $auto_ckpt_interval
# fi

# ============ 1. start of inference block ===========
# cache_file_path=$model_paths_file
# echo "mo\del_paths_file: $model_paths_file, cache_file_path: $cache_file_path"

# if [ ! -e "$model_paths_file" ]; then
#   cache_file_path=$output_dir/$job_name/metrics/cached_img_paths_${dataset}.txt
#   echo "$model_paths_file not exists, use default image path: $cache_file_path"
# fi


if [ "$inference" = true ]; then
  inference_script=${inference_script:-"scripts/inference.py"}
  # cache_file_path=$output_dir/$job_name/metrics/cached_img_paths_${dataset}.txt
  cache_file_path=$metric_dir/cached_img_paths_${dataset}.txt
  echo "cache_file_path: $cache_file_path"
  echo "remove all tmp files in $metric_dir/tmp_${dataset}\*"
  rm $metric_dir/tmp_${dataset}* || true

  read -r -d '' cmd <<EOF
bash scripts/infer_run_inference_single_gpu2.sh $config_file $model_paths_file $work_dir --np=$np \
      --inference_script=$inference_script --step=$step --bs=$bs --sample_nums=$sample_nums --json_file=$json_file \
      --add_label=$add_label \
      --exist_time_prefix=$exist_time_prefix --if_save_dirname=true --sampling_algo=$sampling_algo \
      --cfg_scale=$cfg_scale --dataset=$dataset \
      --ablation_key=$ablation_key --ablation_selections="$ablation_selections" \
      --stich_config=$stich_config
EOF
  echo $cmd
  bash -c "${cmd}"
  > "$cache_file_path"  # clean file
  # add all tmp*.txt file into $cache_file_path
  for file in $metric_dir/tmp_${dataset}*.txt; do
    if [ -f "$file" ]; then
      cat "$file" >> "$cache_file_path"
      echo "" >> "$cache_file_path"   # add new line
    fi
  done
  rm -r $metric_dir/tmp_${dataset}* || true
fi

exp_paths_file=${cache_file_path}
img_path=$(dirname $(dirname $exp_paths_file))/vis
echo "img_path: $img_path, exp_paths_file (cache_file_path): $exp_paths_file"

# ============ 2. start of fid block  =================
if [ "$fid" = true ]; then
  read -r -d '' cmd <<EOF
bash tools/metrics/compute_fid_embedding.sh $img_path $exp_paths_file \
      --sample_nums=$sample_nums --img_size=$img_size --suffix_label=$fid_suffix_label \
      --log_fid=$log_fid --tracker_pattern=$tracker_pattern \
      --tracker_project_name=$tracker_project_name \
      --stich_config=$stich_config
EOF
  echo $cmd
  bash -c "${cmd}"
fi


# ============ 3. start of clip-score block  =================
if [ "$clipscore" = true ]; then
  read -r -d '' cmd <<EOF
bash tools/metrics/compute_clipscore.sh $img_path $exp_paths_file \
      --sample_nums=$sample_nums --suffix_label=$fid_suffix_label \
      --log_clip_score=$log_clip_score --tracker_pattern=$tracker_pattern \
      --tracker_project_name=$tracker_project_name \
      --stich_config=$stich_config
EOF
  echo $cmd
  bash -c "${cmd}"
fi

# ============ 4. start of image-reward block  =================
if [ "$imagereward" = true ]; then
  read -r -d '' cmd <<EOF
bash tools/metrics/compute_imagereward.sh $img_path $exp_paths_file \
      --sample_nums=$sample_nums --suffix_label=$fid_suffix_label \
      --log_image_reward=$log_image_reward --tracker_pattern=$tracker_pattern \
      --tracker_project_name=$tracker_project_name \
      --stich_config=$stich_config
EOF
  echo $cmd
  bash -c "${cmd}"
fi

# # ============ 4. start of dpg-bench block  =================
# if [ "$dpg" = true ]; then
#   read -r -d '' cmd <<EOF
# bash tools/metrics/compute_dpg.sh $img_path $exp_paths_file \
#       --sample_nums=$sample_nums --img_size=$img_size --suffix_label=$fid_suffix_label \
#       --log_dpg=$log_dpg --tracker_pattern=$tracker_pattern \
#       --tracker_project_name=$tracker_project_name \
#       --stich_config=$stich_config
# EOF
#   echo $cmd
#   bash -c "${cmd}"
# fi

# # ============ 5. start of hpsv2 block  =================
# if [ "$hps" = true ]; then
#   read -r -d '' cmd <<EOF
# bash tools/metrics/compute_hpsv2.sh $img_path $exp_paths_file \
#       --sample_nums=$sample_nums --suffix_label=$fid_suffix_label \
#       --log_hpsv2=$log_hpsv2 --tracker_pattern=$tracker_pattern \
#       --tracker_project_name=$tracker_project_name \
#       --stich_config=$stich_config
# EOF
#   echo $cmd
#   bash -c "${cmd}"
# fi

# ============ 6. start of cleanup block  =================
if [ "$cleanup" = true ]; then
  echo "Cleaning up generated images and paths files at $img_path..."

  while IFS= read -r folder || [ -n "$folder" ]; do
    if [ ! -z "$folder" ]; then
      folder_path="$img_path/$folder"
      if [ -d "$folder_path" ]; then
        echo "Removing folder: $folder_path"
        rm -r "$folder_path"
      fi
    fi
  done < "$exp_paths_file"

  echo "Cleanup completed"
fi
