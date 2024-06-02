#!/bin/bash

# ユーザごとのCPU使用率、メモリ使用率、各GPUごとのGPU使用率、スワップ使用率を出力するスクリプト

# 一時ファイルを作成
cpu_file=$(mktemp)
mem_file=$(mktemp)
swap_file=$(mktemp)

# 総スワップ量を取得 (KB単位)
total_swap=$(grep SwapTotal /proc/meminfo | awk '{print $2}')

# 各GPUの名称と総メモリ容量を取得
gpu_info=$(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader,nounits)

# 全ユーザのリストを取得
users=$(ps -eo user= | sort | uniq)

# ヘッダを表示
header="ユーザ       CPU使用率(%)   メモリ使用率(%)   "
gpu_index=0
while IFS=, read -r gpu_index gpu_name total_gpu_mem; do
  header+="GPU${gpu_index}使用率(${gpu_name})(%)   "
done <<< "$gpu_info"
header+="スワップ使用率(%)"
echo $header

# 各ユーザについてループ
for user in $users; do
  # CPU使用率を取得
  ps -u $user -o %cpu= | awk '{sum += $1} END {print sum}' > $cpu_file

  # メモリ使用率を取得
  ps -u $user -o %mem= | awk '{sum += $1} END {print sum}' > $mem_file

  # GPU使用率を取得
  gpu_usage_per_gpu=()
  while IFS=, read -r gpu_index gpu_name total_gpu_mem; do
    user_gpu_usage=0
    while read -r pid; do
      if [ -n "$pid" ]; then
        gpu_mem=$(nvidia-smi --query-compute-apps=pid,gpu_uuid,used_gpu_memory --format=csv,noheader,nounits | awk -v pid="$pid" -v gpu_index="$gpu_index" -F ', ' '$1 == pid && $2 ~ /'$gpu_index'/ {print $3}')
        if [ -n "$gpu_mem" ]; then
          user_gpu_usage=$((user_gpu_usage + gpu_mem))
        fi
      fi
    done < <(pgrep -u $user)

    if [ "$total_gpu_mem" -ne 0 ]; then
      gpu_usage_percent=$(echo "scale=2; ($user_gpu_usage / $total_gpu_mem) * 100" | bc)
    else
      gpu_usage_percent=0
    fi
    gpu_usage_per_gpu+=($gpu_usage_percent)
  done <<< "$gpu_info"

  # スワップ使用率を取得
  user_swap=0
  for pid in $(pgrep -u $user); do
    proc_swap=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
    if [ -n "$proc_swap" ]; then
      user_swap=$((user_swap + proc_swap))
    fi
  done

  if [ "$total_swap" -ne 0 ]; then
    swap_usage=$(echo "scale=2; ($user_swap / $total_swap) * 100" | bc)
  else
    swap_usage=0
  fi

  # 一時ファイルから値を読み取る
  cpu_usage=$(cat $cpu_file)
  mem_usage=$(cat $mem_file)

  # NULLの場合は0に設定
  if [ -z "$cpu_usage" ]; then
    cpu_usage=0
  fi

  if [ -z "$mem_usage" ]; then
    mem_usage=0
  fi

  # 結果を表示
  printf "%-10s %-15.2f %-15.2f " "$user" "$cpu_usage" "$mem_usage"
  for gpu_usage in "${gpu_usage_per_gpu[@]}"; do
    printf "%-15.2f " "$gpu_usage"
  done
  printf "%-15.2f\n" "$swap_usage"
done

# 一時ファイルを削除
rm -f $cpu_file $mem_file $swap_file

