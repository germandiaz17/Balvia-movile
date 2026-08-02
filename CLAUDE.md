# Balvia Mobile — Contexto del proyecto (Flutter)

> App móvil de Balvia. Eres el **Agente Flutter**: implementas la app y CONSUMES el contrato del
> backend (no lo inventas). La fuente de verdad del contrato es hoy el vault de Obsidian
> (`~/Documents/Balvia Brain/02 — Arquitectura/`) y, en última instancia, los handlers de
> `../Balvia-backend/internal/handlers/`. `../Balvia-backend/docs/API_CONTRACT.md` está pendiente de
> generar.

## 1. Producto
Finanzas personales con IA para Colombia. UX clave: **registro de gasto en <5s** vía modal flotante, input por voz, categorización con IA, **offline-first** con sincronización. Idioma es-CO. Solo Android para el MVP (iOS futuro).

## 2. Stack (ya decidido, no re-litigar)
- **Flutter + Dart** (org `co.balvia`, package `balvia_mobile`). Solo Android.
- **State management**: **Riverpod**.
- **BD local**: SQLite vía **Drift** — fuente de verdad offline. **`schemaVersion = 2`** (la v2 añadió
  `ai_categorized`/`ai_confidence`/`ai_suggested_category_id` a `transactions`). Al tocar
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

### Dos capas de lectura (regla para no confundirlas)
Coexisten a propósito:
- **Catálogos y transacciones** → local, desde `lib/core/sync_providers.dart` (`StreamProvider` sobre
  Drift): cuentas, categorías, periodo activo, transacciones.
- **Todo lo demás** → red, desde `lib/core/providers.dart` (`FutureProvider.autoDispose`): budgets,
  insights, metas, recurrentes, settings.

Al añadir una entidad nueva, va por red salvo que `/sync/push` la soporte.

## 4. Concepto de dominio: el "seguimiento" (tracking_period)
Unidad temporal raíz (28–31 días), 1 activa por usuario; toda transacción pertenece a una. El backend la asigna automáticamente (el cliente NO la elige al crear una transacción). Vistas en UI: completa / quincenal / semanal (se calculan, no se almacenan). Detalle en `../Balvia-backend/CLAUDE.md` §3.

**Regla 8**: los cambios en la configuración del seguimiento (duración) aplican al **siguiente**
seguimiento, nunca al activo. La UI debe decirlo explícitamente, con la fecha de corte real.

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
├── features/        # auth, home, transactions, budgets, accounts, categories,
│                    # profile, shell, overlay, ai, dashboard (muerto: no enrutado)
└── shared/          # widgets reutilizables (empty_state, insight_card, sync_status_icon, …)
```
Rutas del shell (4 tabs + FAB de captura): `/home`, `/transactions`, `/budgets`, `/profile`.
Rutas push: `/categories`, `/accounts`, `/overlay-settings`, `/ai-settings`.

## 6. Convenciones
- `dart format` + `flutter analyze` limpio. Tests con `flutter test`.
- Inglés en código/comentarios; UI en español (es-CO).
- Modelos espejo del contrato; `Decimal` para montos; fechas-solo-día como `DateTime` normalizado.
- Pruébalo en emulador, no solo que compile.

## 7. Estado y siguiente hito

**Construido**: auth + splash/redirect, shell de 4 tabs con FAB de captura rápida, CRUD de
transacciones / cuentas / categorías / presupuestos, burbuja flotante Android (overlay), motor de
sync offline-first, carrusel de insights en Home, y categorización con IA (BYOK).

**Hito actual — cerrar el MVP de producto**: metas de ahorro y transacciones recurrentes tienen el
backend 100% listo y **cero UI** (aparecen como tiles "Próximamente" en Perfil); falta también la
pantalla de configuración del seguimiento contra el nuevo `GET/PUT /api/v1/settings`.

**Pendientes conocidos**: input por voz (botón deshabilitado en captura), recuperación de contraseña,
notificaciones, gráficas/reportes, onboarding de usuario nuevo, moneda hardcodeada a `'COP'`, sin
`intl`/localización, `lib/features/dashboard/dashboard_screen.dart` es código muerto (no enrutado),
cero widget tests (los ~221 son unitarios), y release readiness de Android sin empezar (firma con
keystore de debug, icono por defecto, `usesCleartextTraffic=true`).
