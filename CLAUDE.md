# Balvia Mobile — Contexto del proyecto (Flutter)

> App móvil de Balvia. Lee también la raíz `../CLAUDE.md`, `../docs/API_CONTRACT.md` y `../docs/ROADMAP.md`.
> Eres el **Agente Flutter**: implementas la app y CONSUMES el contrato del backend (no lo inventas).

## 1. Producto
Finanzas personales con IA para Colombia. UX clave: **registro de gasto en <5s** vía modal flotante, input por voz, categorización con IA, **offline-first** con sincronización. Idioma es-CO. Solo Android para el MVP (iOS futuro).

## 2. Stack
- **Flutter + Dart** (proyecto creado con `flutter create`, org `co.balvia`, package `balvia_mobile`).
- **BD local**: SQLite vía **Drift** (recomendado) o sqflite — fuente de verdad offline.
- **State management**: por DECIDIR (BLoC vs Provider vs Riverpod) — ver `../docs/ROADMAP.md`. Validar con el humano.
- **HTTP**: `dio` o `http` + interceptor de auth.
- **Tokens**: `flutter_secure_storage`.
- **Dinero**: paquete `decimal` (`Decimal`), NUNCA `double`.

## 3. Backend / API
- Contrato: `../docs/API_CONTRACT.md` (única fuente de verdad). Base URL dev: `http://10.0.2.2:8080/api/v1` (emulador Android → host).
- Auth: Bearer access token (~24h) + refresh token (~30d, rotado). Interceptor: añade `Authorization`, y en `401` intenta `POST /auth/refresh` una vez; si falla → logout.
- Estado del backend hoy (consumible): auth, accounts, categories, transactions. NO existen aún: budgets, metas, insights, sync → stubbea local hasta que el contrato los liste.

## 4. Concepto de dominio: el "seguimiento" (tracking_period)
Unidad temporal raíz (28–31 días), 1 activa por usuario; toda transacción pertenece a una. El backend la asigna automáticamente (el cliente NO la elige al crear una transacción). Vistas en UI: completa / quincenal / semanal (se calculan, no se almacenan). Detalle en `../balvia-backend/CLAUDE.md` §3.

## 5. Estructura sugerida (proponer/validar al empezar)
```
lib/
├── main.dart
├── core/            # config, theme, http client, errores, di
├── data/            # drift db, models, repositorios, api clients
├── features/        # auth, accounts, categories, transactions, dashboard (capture rápido)
└── shared/          # widgets reutilizables
```

## 6. Convenciones
- `dart format` + `flutter analyze` limpio. Tests con `flutter test`.
- Inglés en código/comentarios; UI en español (es-CO).
- Modelos espejo del contrato; `Decimal` para montos; fechas-solo-día como `DateTime` normalizado.
- Pruébalo en emulador, no solo que compile.

## 7. Primeros pasos del roadmap (ver ../docs/ROADMAP.md)
Arquitectura base + theming → cliente HTTP con auth → flujo de login/registro → captura rápida de gasto → dashboard del seguimiento.
