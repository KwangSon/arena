# Setup

## Prerequisites

### Python & pip3

**macOS**
```bash
brew install python3
```

**Debian/Ubuntu**
```bash
sudo apt install python3-pip
```

> Debian 계열은 시스템 정책상 `pip3 install` 직접 실행이 막혀 있으므로 반드시 apt로 설치합니다.

---

## GDToolkit (GDScript linter/formatter)

pip3로 gdtoolkit 4.x를 설치합니다.

```bash
pip3 install "gdtoolkit==4.*"
```

설치 확인:
```bash
gdlint --version
gdformat --version
```

---

## Lint

프로젝트 루트에서 실행합니다.

```bash
# 전체 lint
gdlint res://

# 특정 파일
gdlint src/main.gd
```

## Format

```bash
# 전체 포맷
gdformat res://

# 특정 파일
gdformat src/main.gd
```
