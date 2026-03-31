#!/bin/bash
cd "$(dirname "$0")"
echo "📦 hey-mini-game git push 시작..."
echo "현재 브랜치:"
git log --oneline -3
echo ""
git push origin main
echo ""
echo "✅ 완료! 이 창을 닫아도 됩니다."
read -p "엔터를 누르면 창이 닫힙니다..."
