#!/bin/bash

# ユーザごとのCPU使用率、メモリ使用率、GPU使用率、スワップ使用率を出力するスクリプト

# 一時ファイルを作成
cpu_file=$(mktemp)
mem_file=$(mktemp)
gpu_file=$(mktemp)
swap_file=$(mktemp)

# 総スワップ量を取得 (KB単位)
total_swap=$(grep SwapTotal /proc/meminfo | awk '{print $2}')

# 全GPUの総メモリ容量を取得 (MB単位)
total_gpu_mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | awk '{sum += $1} END {print sum}')

# 全ユーザのリストを取得
users=$(ps -eo user= | sort | uniq)

# ヘッダを表示
echo "ユーザ       CPU使用率(%)   メモリ使用率(%)   GPU使用率(%)    スワップ使用率(%)"

# 各ユーザについてループ
for user in $users; do
  # CPU使用率を取得
  ps -u $user -o %cpu= | awk '{sum += $1} END {print sum}' > $cpu_file

  # メモリ使用率を取得
  ps -u $user -o %mem= | awk '{sum += $1} END {print sum}' > $mem_file

  # GPU使用率を取得
  user_gpu_usage=0
  while read -r pid; do
    if [ -n "$pid" ]; then
      gpu_mem=$(nvidia-smi --query-compute-apps=pid,used_gpu_memory --format=csv,noheader,nounits | awk -v pid="$pid" -F ',' '$1 == pid {print $2}')
      if [ -n "$gpu_mem" ]; then
        user_gpu_usage=$((user_gpu_usage + gpu_mem))
      fi
    fi
  done < <(pgrep -u $user)

  if [ "$total_gpu_mem" -ne 0 ]; then
    gpu_usage=$(echo "scale=2; ($user_gpu_usage / $total_gpu_mem) * 100" | bc)
  else
    gpu_usage=0
  fi

  echo $gpu_usage > $gpu_file

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
  gpu_usage=$(cat $gpu_file)

  # NULLの場合は0に設定
  if [ -z "$cpu_usage" ]; then
    cpu_usage=0
  fi

  if [ -z "$mem_usage" ]; then
    mem_usage=0
  fi

  if [ -z "$gpu_usage" ]; then
    gpu_usage=0
  fi

  # 結果を表示
  printf "%-10s %-15.2f %-15.2f %-15.2f %-15.2f\n" "$user" "$cpu_usage" "$mem_usage" "$gpu_usage" "$swap_usage"
done

# 一時ファイルを削除
rm -f $cpu_file $mem_file $gpu_file $swap_file

