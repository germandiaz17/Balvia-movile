# Balvia Mobile — Contexto del proyecto (Flutter)

> App móvil de Balvia. Eres el **Agente Flutter**: implementas la app y CONSUMES el contrato del
> backend (no lo inventas). La fuente de verdad del contrato es
> **`../Balvia-backend/docs/API_CONTRACT.md`** y, en última instancia, los handlers de
> `../Balvia-backend/internal/handlers/`. El vault de Obsidian
> (`~/Documents/Balvia Brain/`) guarda la documentación narrativa, no el contrato.

## 1. Producto
Finanzas personales con IA para Colombia. UX clave: **registro de gasto en <5s** vía modal flotante, input por voz, categorización con IA, **offline-first** con sincronización. Idioma es-CO. Solo Android para el MVP (iOS futuro).

## 2. Stack (ya decidido, no re-litigar)
- **Flutter + Dart** (org `co.balvia`, package `balvia_mobile`). Solo Android.
- **State management**: **Riverpod**.
- **BD local**: SQLite vía **Drift** — fuente de verdad offline. **`schemaVersion = 3`** (la v2 añadió
  los campos `ai_*` a `transactions`; la v3, `config_period_mode`/`is_transition` a
  `tracking_periods`). Al tocar
  `lib/data/local/tables.dart` hay que subir la versión, escribir el `onUpgrade` y correr
  `dart run build_runner build --delete-conflicting-outputs`.
- **HTTP**: `dio` + interceptor de auth. **Tokens**: `flutter_secure_storage`.
- **Dinero**: paquete `decimal` (`Decimal`), NUNCA `double`.

## 3. Backend / API
- Base URL dev: `http://10.0.2.2:8080/api/v1` (emulador Android → host), override con
  `--dart-define=API_BASE_URL`.
- Auth: Bearer access token + refresh token rotado. El interceptor añade `Authorization` y en `401`
  intenta `POST /auth/refresh` una vez; si falla → logout.
- **Consumible hoy**: auth, accounts, categories, transactions, budgets, tracking-periods (+summary
  +insights), savings-goals, recurring-transactions, sync (pull/push), ai (settings + categorize).
- **Límites del backend que condicionan la app**:
  - `POST /sync/push` **solo acepta `entity_type: "transaction"`**. El pull trae 8 entidades, pero
    todo lo demás se muta por red. Por eso las escrituras offline solo existen para transacciones.
  - `GET /recurring-transactions` **tiene efecto secundario**: dispara el motor de materialización y
    puede crear transacciones reales. Tras llamarlo, sincroniza.
  - El `PUT` de savings-goals y recurring-transactions es **replace completo** → precarga el form
    entero antes de editar.
  - El `PUT` de accounts también es replace completo, salvo `initial_balance`, que es **opcional**:
    omítelo para no tocar el saldo de apertura. Mandarlo solo se acepta mientras la cuenta no tenga
    movimientos (si los tiene → 422).

### Dos capas de lectura (regla para no confundirlas)
Coexisten a propósito:
- **Catálogos y transacciones** → local, desde `lib/core/sync_providers.dart` (`StreamProvider` sobre
  Drift): cuentas, categorías, periodo activo, transacciones.
- **Todo lo demás** → red, desde `lib/core/providers.dart` (`FutureProvider.autoDispose`): budgets,
  insights, metas, recurrentes, settings.

Al añadir una entidad nueva, va por red salvo que `/sync/push` la soporte.

## 4. Concepto de dominio: el "seguimiento" (tracking_period)
Unidad temporal raíz (28–31 días), 1 activa por usuario; toda transacción pertenece a una. El backend la asigna automáticamente (el cliente NO la elige al crear una transacción). Vistas en UI: completa / quincenal / semanal (se calculan, no se almacenan). Detalle en `../Balvia-backend/CLAUDE.md` §3.

**Dos modos**, elegibles por el usuario: `rolling` (bloques de duración fija) y `calendar_month`
(meses reales). Un periodo trae `configPeriodMode` e `isTransition`:
- `isWholeCalendarMonth` → titúlalo con el nombre del mes (`monthTitle`), no con un rango.
- `isTransition` → es un **puente** de 15–45 días creado al cambiar de modo. Márcalo como tal; no es
  un seguimiento normal y su duración no es comparable.

**Regla 8**: los cambios en la configuración del seguimiento (duración o modo) aplican al
**siguiente** seguimiento, nunca al activo. La UI debe decirlo explícitamente, con la fecha de corte
real — y, al pasar a modo calendario, con las fechas exactas del puente. La única excepción es un
primer periodo sin transacciones, que el backend reforma en sitio y reporta con
`appliesToNextPeriod == false`.

`lib/core/period_math.dart` replica la aritmética de `internal/domain/period.go` para poder
previsualizar el puente antes de guardar. Es duplicación deliberada: las dos tablas de tests son
idénticas y deben mantenerse así.

## 5. Estructura real
```
lib/
├── main.dart
├── core/            # config, theme, router, api_client, api_error, providers, sync_providers
├── data/
│   ├── local/       # drift: tables.dart, app_database.dart (+ .g.dart), DAOs
│   ├── models/      # espejos del contrato del backend
│   ├── repositories/# de red (dio) y locales (drift)
│   └── sync/        # sync_engine.dart (pull paginado + push por outbox)
├── features/        # auth, onboarding, home, transactions, budgets, accounts, categories,
│                    # profile, shell, overlay, ai, dashboard (muerto: no enrutado)
└── shared/          # widgets reutilizables (empty_state, insight_card, sync_status_icon, …)
```
Rutas del shell (4 tabs + FAB de captura): `/home`, `/transactions`, `/budgets`, `/profile`.
Rutas push: `/categories`, `/accounts`, `/overlay-settings`, `/ai-settings`, `/savings-goals`,
`/recurring`, `/tracking-settings`.
Ruta de primer arranque: `/onboarding` — el redirect del router la antepone a **todo** destino
mientras `onboardingControllerProvider` sea `true`.

## 6. Convenciones
- `dart format` + `flutter analyze` limpio. Tests con `flutter test`.
- Inglés en código/comentarios; UI en español (es-CO).
- Modelos espejo del contrato; `Decimal` para montos; fechas-solo-día como `DateTime` normalizado.
- Pruébalo en emulador, no solo que compile.

## 7. Estado y siguiente hito

**Construido**: auth + splash/redirect, shell de 4 tabs con FAB de captura rápida, CRUD de
transacciones / cuentas / categorías / presupuestos, metas de ahorro, transacciones recurrentes,
configuración del seguimiento (modo + duración), burbuja flotante Android (overlay), motor de sync
offline-first, carrusel de insights en Home, categorización con IA (BYOK), **onboarding de usuario
nuevo** y **seguimientos por mes calendario**.

**Sin hito en curso.** Los dos últimos cerrados: "onboarding de usuario nuevo" (2026-08-03) y
"modo de seguimiento por mes calendario" (2026-08-08). Candidatos siguientes en
`../Balvia-backend/docs/ROADMAP.md`.

### Onboarding (`lib/features/onboarding/`)
Wizard de 3 pasos que corre una sola vez tras el registro: qué es el seguimiento (con las fechas
reales del periodo activo), nombre + saldo inicial de la primera cuenta, y dónde está la captura.
Dos detalles que importan:
- El disparador es un flag en SharedPreferences **por user id** (`OnboardingController`), no una
  columna del backend: es estado de UI y no justifica una migración. `AuthController` lo pone en
  `register()` y lo restaura en `login()`/`_bootstrap()`.
- El paso de la cuenta lee cuentas **por red** (`onboardingAccountsProvider`), no de Drift: corre
  segundos después del registro, antes de que el primer pull haya aterrizado. Es la excepción
  deliberada a la regla de las dos capas de lectura.
Todo el wizard es omitible: el backend ya garantiza que existe una cuenta usable.

**Pendientes conocidos**: input por voz (botón deshabilitado en captura), recuperación de contraseña,
notificaciones, gráficas/reportes, moneda hardcodeada a `'COP'`, sin `intl`/localización,
`lib/features/dashboard/dashboard_screen.dart` es código muerto (no enrutado), cero widget tests
(los 336 son unitarios), y release readiness de Android sin empezar (firma con keystore de debug,
icono por defecto, `usesCleartextTraffic=true`).
