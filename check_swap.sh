#!/bin/bash

# Swapを使用しているプロセスとそのユーザ、スワップ量を表示するスクリプト

echo "ユーザ      プロセスID      スワップ量(GB)      コマンド"

# /proc ディレクトリの中をループして、各プロセスのスワップ使用量を調査
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  # プロセスのステータスファイルを読み込む
  status_file="/proc/$pid/status"
  
  # ステータスファイルが存在するか確認
  if [ -f "$status_file" ]; then
    # VmSwap行を抽出
    swap=$(grep VmSwap $status_file | awk '{print $2}')
    
    # VmSwapが存在しない場合は0に設定
    if [ -z "$swap" ]; then
      swap=0
    fi
    
    # スワップが0でない場合のみ表示
    if [ "$swap" -gt 0 ]; then
      # プロセスのユーザを取得
      user=$(ps -o user= -p $pid)
      
      # プロセスのコマンドを取得
      cmd=$(ps -o cmd= -p $pid)
      
      # スワップ量をGBに変換
      swap_gb=$(echo "scale=6; $swap / (1024 * 1024)" | bc)
      
      # 情報を表示
      printf "%-10s %-12d %-16.6f %s\n" "$user" "$pid" "$swap_gb" "$cmd"
    fi
  fi
done | sort -k3 -nr | head -n 10

