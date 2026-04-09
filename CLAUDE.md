# CLAUDE.md - Hey Mini Game

이 저장소는 **Youngssoo 앱**에서 웹뷰로 실행되는 미니게임을 개발하는 프로젝트입니다.
각 게임은 단일 `index.html` 파일로 구성된 순수 웹 게임이며, Firebase Hosting으로 배포됩니다.

## 프로젝트 구조

```
games/
├── CLAUDE.md              # 이 문서 (개발 규약)
├── GAME_DEV_GUIDE.md      # 상세 개발 가이드
├── firebase.json          # Firebase Hosting 설정
├── template/              # 새 게임 시작용 템플릿
│   └── index.html
├── flappy-bird/           # 플래피버드 게임
│   └── index.html
├── sky-stairs/            # 하늘 계단 게임
│   ├── index.html
│   ├── left.png
│   └── right.png
└── puzzle-marble/         # 퍼즐버블 게임
    └── index.html
```

## 핵심 규칙

### 1. 게임 파일 구조
- 각 게임은 `games/[game-name]/index.html` 단일 파일로 만든다
- CSS, JS는 모두 index.html 안에 인라인으로 작성한다
- 이미지 에셋이 필요하면 같은 폴더에 넣는다
- 외부 CDN 의존성은 최소화한다 (오프라인에서도 작동해야 함)

### 2. 필수 구현: GameBridge (앱 ↔ 게임 통신)

모든 게임은 반드시 `GameBridge` 객체를 구현해야 한다. 이것이 앱과 게임 사이의 유일한 통신 채널이다.

```javascript
const GameBridge = {
    stage: 1,
    highScore: 0,
    customData: {},

    // [필수] 앱이 호출함 - 게임 초기화 데이터 수신
    onInit: function(data) {
        // data = { stage: number, highScore: number, customData: string(JSON) }
        this.stage = data.stage || 1;
        this.highScore = data.highScore || 0;
        this.customData = JSON.parse(data.customData || '{}');
        startGame(); // 게임 시작 함수 호출
    },

    // [필수] 게임이 호출함 - 점수 실시간 업데이트
    updateScore: function(score) {
        if (window.AndroidBridge) {
            AndroidBridge.updateScore(score);
        } else if (window.webkit?.messageHandlers?.iOSBridge) {
            webkit.messageHandlers.iOSBridge.postMessage({
                type: 'updateScore', score: score
            });
        }
    },

    // [필수] 게임이 호출함 - 게임 완료 시
    complete: function(result) {
        // result = { score: number, cleared: boolean, customData: object }
        const payload = JSON.stringify(result);
        if (window.AndroidBridge) {
            AndroidBridge.gameComplete(payload);
        } else if (window.webkit?.messageHandlers?.iOSBridge) {
            webkit.messageHandlers.iOSBridge.postMessage({
                type: 'gameComplete',
                score: result.score,
                cleared: result.cleared,
                customData: JSON.stringify(result.customData || {})
            });
        } else {
            // 브라우저 테스트 모드
            alert(`게임 완료!\n점수: ${result.score}\n클리어: ${result.cleared ? '성공' : '실패'}`);
            location.reload();
        }
    },

    // [선택] 게임 중간 저장
    saveData: function(data) {
        const payload = JSON.stringify(data);
        if (window.AndroidBridge) {
            AndroidBridge.saveData(payload);
        } else if (window.webkit?.messageHandlers?.iOSBridge) {
            webkit.messageHandlers.iOSBridge.postMessage({
                type: 'saveData', data: payload
            });
        }
    },

    // [선택] 디버그 로그
    log: function(message) {
        console.log('[GameBridge]', message);
        if (window.AndroidBridge) {
            AndroidBridge.log(message);
        }
    }
};
```

#### Android 네이티브 브릿지 메서드 (앱에서 제공)
- `AndroidBridge.updateScore(score)` - 점수 업데이트
- `AndroidBridge.gameComplete(jsonPayload)` - 게임 완료
- `AndroidBridge.saveData(jsonPayload)` - 데이터 저장
- `AndroidBridge.log(message)` - 로그

#### iOS 네이티브 브릿지 메서드 (앱에서 제공)
- `webkit.messageHandlers.iOSBridge.postMessage({type, ...})` - 모든 통신은 이 채널로

#### GameBridge 구현 필수 사항 ⚠️

1. **window.GameBridge 전역 할당** (반드시 필수)
   ```javascript
   const GameBridge = { ... };
   window.GameBridge = GameBridge;  // ← 이 줄이 필수!
   ```

2. **중복 초기화 방지**
   ```javascript
   const GameBridge = {
       initialized: false,
       onInit(data) {
           if (this.initialized) return;  // 중복 호출 방지
           this.initialized = true;
           // ...
       }
   };
   ```

3. **타입 안전 파싱**
   ```javascript
   onInit(data) {
       // 문자열/객체 모두 지원
       if (typeof data === 'string') data = JSON.parse(data);
       this.customData = typeof data.customData === 'string'
           ? JSON.parse(data.customData || '{}')
           : (data.customData || {});
   }
   ```

### 3. 필수: 앱 호환성 설정

#### ⚠️ CSS에서 color-scheme 설정
```html
<style>
  :root { color-scheme: dark; }  /* ← 반드시 추가! */
  html, body { width:100%; height:100%; overflow:hidden; }
</style>
```

#### ⚠️ 앱 호출 타임아웃 자동 초기화 (300ms)
**주의: 타임아웃은 300ms 이상 길게 설정하지 마세요! 게임 시작이 지연됩니다.**

```javascript
const isTestMode = !window.AndroidBridge && !window.webkit?.messageHandlers?.iOSBridge;

if (!isTestMode) {
  // 앱 호출 대기, 300ms 후 자동 초기화 (게임 시작 지연 방지)
  setTimeout(() => {
    if (!GameBridge.initialized) {
      console.warn('[GameBridge] 앱 호출 없이 자동 초기화');
      GameBridge.onInit({ stage:1, highScore:0, customData:'{}' });
    }
  }, 300);  // ← 300ms 권장 (800ms 이상 설정 금지!)
}
```

### 4. 필수 구현: 테스트 모드

앱 없이 브라우저에서 테스트할 수 있도록, 앱 브릿지가 없으면 테스트 패널을 표시해야 한다.

```javascript
const isTestMode = !window.AndroidBridge && !window.webkit?.messageHandlers?.iOSBridge;

if (isTestMode) {
    // 스테이지, 최고점수, 커스텀데이터를 입력받는 테스트 패널 표시
    // "게임 시작" 버튼 클릭 시 GameBridge.onInit() 호출
} else {
    // 앱에서 실행 시 테스트 패널 숨김 - 앱이 GameBridge.onInit()을 호출함
}
```

### 5. 난이도 시스템

스테이지(stage)에 따라 난이도가 점진적으로 증가해야 한다.

```javascript
function getDifficulty(stage) {
    return {
        timeLimit: Math.max(30, 120 - (stage - 1) * 5),      // 시간제한(초) - 점점 짧아짐
        targetScore: 100 + (stage - 1) * 50,                   // 목표점수 - 점점 높아짐
        speedMultiplier: 1 + (stage - 1) * 0.1,               // 속도 배율
        complexity: Math.min(10, 1 + Math.floor((stage - 1) / 3)) // 복잡도(1~10)
    };
}
```

- 게임별로 난이도 파라미터는 자유롭게 조정 가능
- 핵심은 **stage가 올라갈수록 어려워져야 한다**는 것

### 6. 스테이지 클리어 조건

```javascript
function onGameOver(score, stage) {
    const cleared = score >= getDifficulty(stage).targetScore;
    GameBridge.complete({
        score: score,
        cleared: cleared,
        customData: { /* 게임별 저장 데이터 */ }
    });
}
```

- `cleared: true` → 앱에서 다음 스테이지 진행 가능
- `cleared: false` → 앱에서 같은 스테이지 재시도

### 7. UI/UX 필수 요건

- **모바일 우선**: 터치 입력 기반, `user-scalable=no`
- **전체 화면**: `100vw x 100vh`, `overflow: hidden`
- **Safe Area 대응**: `viewport-fit=cover`
- **필수 meta 태그**:
  ```html
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  ```
- **터치 이벤트 최적화**: `touch-action: none` (불필요한 브라우저 제스처 방지)
- **어두운 테마**: 기본 배경은 어두운 색 계열 (`#1a1a2e` 등)

### 8. 대상 사용자

- **초등학생** 대상 교육 앱의 보상용 미니게임
- 조작이 단순하고 직관적이어야 함
- 게임 한 판은 1~3분 내로 끝나야 함
- 폭력적이거나 자극적인 콘텐츠 금지

## 새 게임 만들기

1. `template/index.html`을 `[game-name]/index.html`로 복사
2. 게임 로직 구현 (GameBridge 필수)
3. 브라우저 테스트 모드로 동작 확인
4. Firebase Hosting으로 배포: `firebase deploy --only hosting`
5. Firestore `mini_games` 컬렉션에 게임 등록 (아래 참고)

## Firestore 게임 등록 (앱에서 게임 목록 표시용)

게임 배포 후, Firebase Console에서 `mini_games` 컬렉션에 문서를 추가해야 앱에 표시된다.

**컬렉션 경로**: `mini_games`
**문서 ID**: 게임 폴더명 (예: `flappy-bird`)

| 필드 | 타입 | 필수 | 설명 | 예시 |
|------|------|------|------|------|
| `name` | string | O | 게임 이름 | `"플래피버드"` |
| `description` | string | O | 게임 설명 | `"파이프를 피해 날아가세요!"` |
| `gameUrl` | string | O | 게임 URL | `"https://heyyoungssoo.web.app/flappy-bird/"` |
| `thumbnailUrl` | string | | 썸네일 URL | |
| `costType` | string | O | `"PLAYS"` 또는 `"TIME"` | `"PLAYS"` |
| `costAmount` | number | O | 플레이 비용 (포인트) | `50` |
| `playValue` | number | O | 판수 또는 초 (9999=무제한) | `9999` |
| `unlockPrice` | number | O | 영구 해금 가격 (포인트) | `500` |
| `version` | number | O | 게임 HTML 버전 (HTML 업데이트 시 +1) | `1` |
| `isActive` | boolean | | 활성화 여부 (기본 true) | `true` |
| `order` | number | | 정렬 순서 (낮을수록 위) | `1` |

## 배포

```bash
# Firebase CLI로 배포
firebase deploy --only hosting

# 배포 URL: https://heyyoungssoo.web.app/[game-name]/
```

## 체크리스트 (배포 전)

### 기능 구현
- [ ] `GameBridge.onInit()` 구현됨
- [ ] `GameBridge.complete()` 호출됨 (게임 종료 시)
- [ ] `GameBridge.updateScore()` 호출됨 (점수 변경 시)
- [ ] 테스트 모드에서 정상 작동
- [ ] 난이도가 스테이지에 따라 증가
- [ ] 스테이지 클리어 조건 명확
- [ ] 모바일 터치 입력 지원
- [ ] 가로/세로 화면 대응 (또는 세로 고정)
- [ ] 1~3분 내 한 판 완료 가능

### 앱 호환성 (반드시 필수!)
- [ ] `window.GameBridge = GameBridge;` 전역 할당됨
- [ ] `GameBridge.initialized` 플래그로 중복 초기화 방지
- [ ] CSS에 `:root { color-scheme: dark; }` 추가됨
- [ ] 앱 호출 없을 때 자동 초기화 타임아웃 추가됨 (800ms)
- [ ] 메타 태그에 `viewport-fit=cover` 포함됨

### Firebase 설정
- [ ] Firestore `mini_games` 컬렉션에 게임 문서 추가
- [ ] `unlockPrice` (number) 필드 추가
- [ ] `version` (number) 필드 추가
