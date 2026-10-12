# Frontend Style Guide

Rules for the React app in `src/frontend`. Written for coding agents: follow the rules as stated;
when a rule says "use X", don't build an alternative.

Stack: React 18, Vite, MUI 6 (+ x-charts, x-date-pickers), Tailwind 3, Redux Toolkit + RTK Query,
react-hook-form, react-router-dom 7, notistack, CASL, Vitest + Testing Library. Plain JavaScript.
Node 22.

## 0. Before you write code

1. Find the screen's neighbours: `pages/dashboard/<domain>/`, `components/<domain>/`,
   `components/forms/<domain>/`, `components/dialog/<domain>/`.
2. Search for something that already does it before creating a component, hook or helper:
   `components/inputs/`, `components/dialog/`, `components/tables/`, `components/buttons/`,
   `hooks/`, `utils/`. Reuse it as-is or extend it; never copy it.
3. Check `app/api/endpoints/<domain>.jsx` for the endpoint and `app/enum.js` for the choice list.
4. Check the backend serializer for real field names and shapes; never guess a response shape.
5. Copy the structure of the inventory module (section 3), the reference implementation.
6. When done: `npm run lint`, `npm test` (single file: `npx vitest run <path>`), and mobile width.
   Pre-commit only runs Prettier; ESLint and Vitest are not run for you.

## 1. Tooling

- Prettier (`.prettierrc`): 100 cols, 2 spaces, double quotes, semicolons, `trailingComma: "es5"`.
- ESLint (`eslint.config.js`): react, react-hooks, simple-import-sort, unused-imports.
  Run `npm run lint`, `lint:fix`, `format`, `test`. `npm run dev` runs the Vite dev server.
- No PropTypes, no `console.log` (`warn`/`error` fine). `eqeqeq` (`== null` allowed), `prefer-const`,
  no nested ternaries.
- Prefix intentionally unused vars with `_`; mark omitted hook deps with
  `// eslint-disable-line react-hooks/exhaustive-deps`.
- New dependency only when nothing installed covers it; never a second library for the same job.

## 2. Imports

`@/` alias (`src/frontend/*`) for anything outside the current folder; relative only for siblings.
Group order (sorted by `lint:fix`): react/router, third-party, `@/`, relative, styles last. Import
files directly; no barrel `index` files.

## 3. Directory layout (type first, then domain)

```
app/          store, router, theme, enum.js, api/ (RTK Query), slices/
components/   inputs/  forms/<domain>/  dialog/<domain>/  buttons/  banners/  tables/  <domain>/
hooks/        all reusable hooks
layouts/      DashboardLayout, Website, AdminContent
pages/        routed screens only: pages/dashboard/<domain>/<Screen>.jsx
utils/        pure helpers + tests
```

| File | Location | Example |
| --- | --- | --- |
| Dialog | `components/dialog/<domain>/` | `dialog/inventory/QuantityDialog.jsx` |
| Form fields | `components/forms/<domain>/<X>Form.jsx` | `forms/inventory/StorageLocationForm.jsx` |
| Button / banner | `components/buttons/`, `components/banners/` | `buttons/ExportFileButton.jsx` |
| Hook | `hooks/` | `hooks/usePropertySelector.jsx` |
| Domain constants, `sx` | `components/<domain>/constants.js` | `inventory/constants.js` |
| Tab section / table | `components/<domain>/` | `inventory/StorageLocations.jsx` |
| Tabs screen | `pages/dashboard/<domain>/` | `inventory/InventoryTabs.jsx` |
| Add/Edit screen | `pages/dashboard/<domain>/` | `inventory/EditStorageLocation.jsx` |
| Endpoints | `app/api/endpoints/<domain>.jsx` | `endpoints/inventory.jsx` |

The inventory module is the reference. New dialogs go only in `components/dialog/`.

## 4. Naming

- Components: PascalCase file = default export. Hooks: `useX.js(x)`, default export. Pure logic:
  camelCase `.js`; `.jsx` only with JSX. New domain folders are camelCase.
- Handlers `handleX` inside, props `onX` outward. Booleans `isX` / `hasX` / `canX`.
- Tests next to the file (`X.test.jsx`), split by scenario suffix (`PricingForm.fees.test.jsx`).
- Use the backend's names: API fields stay snake_case in payloads and form field `name`s; UI and
  component names use the domain terms in section 24.

## 5. Components

- Function components, default export; named exports for secondary pieces (constants, contexts).
- Destructure props with defaults in the signature. Short JSDoc says what it's for; comments explain
  *why*. No commented-out code; a `TODO` names the missing behaviour.
- One job per component: split when a file mixes data fetching, layout and a large sub-UI. The page
  owns data; children get values and `onX` callbacks.
- No prop drilling: if a nested child needs the route's id or a filter, read it with `useParams` /
  `useSearchParams` (or call the same RTK Query hook; the cache dedupes) instead of passing it
  through layers.
- Two near-identical components (`XForm` and `XEditForm`) become one parameterised component.
- Shared components stay generic: no domain-specific logic in `BaseForm`, `Datatable`, dialogs or
  inputs; put it in the domain's page or component.
- Hooks at the top level only; derive values during render instead of syncing them via `useEffect`.
- Removing a field or feature: remove every reference (endpoint, hook export, form, columns, tests).

## 6. State: pick the narrowest home

| State | Home |
| --- | --- |
| Server data | RTK Query cache (never copied into a slice or `useState`) |
| Form values | react-hook-form (`BaseForm`) |
| Shareable view state (tab, filters, page) | URL: `useSearchParams` (`?tab=<slug>`) |
| App-wide client state | `app/slices/` (user, modal, header, socket, uploadQueue, dashboardFilters) |
| Ephemeral UI (open, hover, selection) | `useState` |

Slices are accessed through a hook when they need shaping (`hooks/useDashboardFilters.js`).

## 7. Styling and responsive

- MUI + `sx` with theme tokens (`"text.secondary"`, `"primary.main"`) over hex. Theme: `app/theme.jsx`.
- Tailwind `className` for layout/spacing only (`important: true`, so don't restyle MUI with it);
  conditional classes via `cn()` (`utils/classNames.js`). `styled()` only inside shared inputs.
- `Grid2` (`import { Grid2 as Grid } from "@mui/material"`), not `Grid`.
- Icons: `@mui/icons-material` or `react-icons`, matching neighbours. No `lucide-react`.
- Responsive: `sx` breakpoint values (`{ xs: 1, md: 3 }`) for layout; `hooks/useIsMobile.js`
  (below `md`) when the markup itself changes, e.g. filters in a drawer (`dashboard/MobileFilterBar.jsx`).

## 8. Shared inputs: bind them, don't fork them

| Need | Use |
| --- | --- |
| Select (single/multi, filter, "All") | `components/inputs/SelectField.jsx` |
| Labeled text / number / password | `components/inputs/StyledInputWithLabel.jsx` |
| Search box | `components/inputs/SearchInput.jsx` |
| Time in a form | `components/inputs/CustomTimePickerWithLabel.jsx` |
| Date | `components/inputs/CustomDatePicker.jsx` |
| Free-text combobox outside a form | `components/inputs/uncontrolled/ComboboxUnControlledForm.jsx` |
| Property + group pickers | `hooks/usePropertySelector.jsx` |
| Icon action in a table row | `components/buttons/CustomIconButton.jsx` (`title`, `icon`, `onClick`) |

`SelectField` is controlled (`value`, `onChange(next)`, `options = [{ value, label }]`); in forms
bind it through `Controller`:

```jsx
<Controller name="vendor" control={control} render={({ field }) => (
  <SelectField id="vendor" label="Vendor" options={vendorOptions}
    value={field.value} onBlur={field.onBlur} onChange={field.onChange} />
)} />
```

- `CustomTimePickerWithLabel` displays 12-hour by default (`ampm`); set `valueFormat` to the format
  the API expects (e.g. `"HH:mm:ss"`) so display and wire format never get mixed up.
- No wrapper inputs (e.g. `VendorSelect` around `SelectField`); no wrapping MUI primitives that
  already take the prop (`<Alert action={...}>` directly).
- No one-off hooks per dialog or form: shared logic is one reusable component or a hook in `hooks/`.

## 9. Forms: BaseForm

`components/forms/BaseForm.jsx` gives `FormProvider`, reset on new `defaultValues`, dirty-only submit
(`onSubmit(dirtyData, allData)`), DRF error mapping (field `setError`, snackbar for
`detail`/`non_field_errors`), unsaved-changes dialog, sticky Cancel/Save bar, success snackbar +
navigate, read-only mode. The page owns queries, mutations and `onSubmit`; fields live in
`components/forms/<domain>/<X>Form.jsx` and use `useFormContext()`.

```jsx
<BaseForm onSubmit={submit} defaultValues={defaultValues} isLoading={isLoading}
  isSubmitting={updating} readOnly={readOnly} successNavigate={backTo}
  messages={{ success: "Saved.", error: "Could not be saved." }}>
  <StorageLocationForm locationId={id} readOnly={readOnly} />
</BaseForm>
```

- `onSubmit` returns the RTK Query result (`{ data }` / `{ error }`), not `.unwrap()`.
- Domain 409 flows live in the page's `onSubmit`: await a dialog, resubmit, or return `undefined` to
  skip BaseForm's handling:

  ```jsx
  const submit = async (payload) => {
    const response = await updateLocation({ id, data: payload });
    const { status, data: body } = response.error ?? {};
    if (status === 409 && body?.code === "confirm_clear_queued") {
      const choice = await new Promise((resolve) => setPrompt({ rows: body.rows, resolve }));
      setPrompt(null);
      return choice ? submit({ ...payload, clear_queued: choice }) : undefined;
    }
    return response;
  };
  ```
- Never hand-roll page form state or a save bar, or call `useUnsavedChangesWarning` directly.
- Client validation (`rules`) mirrors the backend for UX only; the backend must validate too, and
  its field errors are what BaseForm shows.
- Small dialog forms may use local state; on failure keep the dialog open with the error.

## 10. Data fetching: RTK Query only

- One API, `app/api/baseApi.jsx`; domains in `app/api/endpoints/<domain>.jsx` via `injectEndpoints`.
  Import every hook from `@/app/api/baseApi` (add new hooks to its export list).
- No axios / `fetch` in components.
- Auth is the httpOnly cookie (`credentials: "include"`); never attach tokens or read auth cookies.
- Shapes: query `({ url, params })`, mutation `({ url, method, body })`, updates `({ id, data })`.
  Array params via `prepareQueryParams` (`app/api/utils.jsx`); paginated lists parse `Link` with
  `parseLinkHeader` in `transformResponse`. Conditional queries use `skip`; on-demand reads use the
  `useLazyXQuery` hook.
- Every query `providesTags`; every mutation `invalidatesTags` for **every** screen showing the
  changed data (per-id tags where useful). Register new types in `tagTypes`.
- 401 (logout) and 403 (snackbar) are global; don't repeat them.

## 11. Real-time (websocket)

- One socket, owned by `app/slices/socketSlice.js` (opened by `initializeSocket()` in `App.jsx`,
  reconnects with backoff). Components never open their own `WebSocket`.
- Backend pushes `trigger_refetch` with RTK tag names; the slice calls `invalidateTags`. To make a
  screen live, give its query the right `providesTags`: no component-level socket code.
- Send with `dispatch(sendSocketMessage(payload))`; gate send actions on `state.socket.isConnected`.
- Patch cached lists with `updateQueryData` only when a refetch would lose loaded pages (Inbox).

## 12. File uploads

- Single files: `usePostProfileImageToS3Mutation({ file, path })` (presigned S3 POST, images
  compressed); it resolves to the stored key.
- Bulk/background uploads: `enqueueBatch` in `app/slices/uploadQueueSlice.js`. The `File` goes in
  `app/uploadQueueRegistry.js` (`registerFile`) since Redux holds only serializable metadata;
  `components/uploads/UploadQueueRunner.jsx` uploads, retries and saves; `UploadQueueNotifier` reports.
- Previews via `hooks/useFileUrl.jsx` (handles `File` or URL, revokes object URLs).

## 13. Loading, empty and error states

- Tables: `Datatable` `loading` + `emptyMessage` (say what to do next). Page forms: BaseForm
  `isLoading`. Elsewhere a centered `CircularProgress`; in buttons, `disabled` + small spinner.
- Failed queries: inline `<Alert severity="error" action={<Button onClick={refetch}>Retry</Button>}>`;
  show the reason, never stale or partial values (`dashboard/DashboardErrorState.jsx`).
- Render crashes: route `errorElement` in `app/router.jsx`, not per-component boundaries.

## 14. Notifications and dialogs

- `notistack` `enqueueSnackbar`. One-off mutations outside BaseForm: `hooks/useApiHook.jsx`, never
  hand-rolled success/error snackbars:
  ```jsx
  const { handleApiCall } = useApiHook("Property", "deleted successfully", "Failed to delete");
  await handleApiCall(() => deleteProperty(id)); // snackbar "Property deleted successfully"
  ```
  It falls back to the DRF `detail` / `non_field_errors` / first field error; optional 2nd/3rd args
  of `handleApiCall` override the messages.
- Confirm: `components/dialog/AlertDialog.jsx` (`isOpen`, `onClose`, `onComplete`, `onAbort`,
  `header`, `content`, `successText`, `abortText`, `loading`). Delete:
  `components/dialog/DeleteDialog.jsx` (`isOpen`, `onClose`, `onDelete`, optional
  `confirmationInput`). Build a new dialog only when neither fits.
- Custom dialogs in `components/dialog/<domain>/`; parent owns `open`, dialog reports via
  `onClose` / `onConfirm(payload)` and doesn't save unless that's its job (then `onSaved(result)`).
- One state value holds the item acted on: `const [confirmRemove, setConfirmRemove] = useState(null);`

## 15. Routing, layouts and permissions

- `app/router.jsx` (`createBrowserRouter`); sub-paths from `routerOperationsChoice` in `app/enum.js`
  (`LIST` `""`, `CREATE` `"create"`, `EDIT` `":id/edit"`); breadcrumbs via `handle: { crumb }`.
  Public pages under `layouts/Website.jsx`; `/dashboard` under `ProtectedRoutes` +
  `layouts/DashboardLayout.jsx` (sidebar, banners, `AdminContent` outlet).
- Page title: `<PageWrapper title="...">`. Tabs: `components/StyledTabs.jsx`
  (`tabs = [{ key, label, component }]`) + `?tab=<slug>`.
- `React.lazy` + `Suspense` only for heavy, rarely visited routes; everything else imports eagerly.
- CASL via `hooks/useAbility.jsx` (`ability.can("change", "storagelocation")`; admins manage all).
  Routes: `<PermissionRoute check={predicate} />` with predicates from `utils/permissionUtils.js`.
  Components call `useAbility()`; don't drill `canX` or check roles inline. Prefer read-only over
  hiding the screen. FE checks are UX; the backend enforces.

## 16. Constants and enums

- Backend choices live in `app/enum.js` as `Object.freeze({ KEY: { value, label } })`, matching the
  backend codes; exported from its single `export { ... }` block. Compare with `X.KEY.value`, never
  raw strings. Domain-only constants go in `components/<domain>/constants.js`.
- If the API sends a `<field>_display` label, render it; otherwise take the label from `app/enum.js`.

## 17. Env and config

- Read config via `import.meta.env.VITE_*`; add new keys to `.env-sample`. Read it where it's
  used (`baseApi`, socket slice) rather than in components.
- `VITE_*` values ship in the public bundle: publishable keys only, never secrets.

## 18. Tables, charts, maps, rich text

- Tables: `components/tables/Datatable.jsx` (imported as `DataTable`; TanStack + MUI): `columns`,
  `data`, `loading`, `emptyMessage`, optional server `sorting`/`onSortingChange` and
  `page`/`pageCount`/`onPageChange`, `onRowClick`. Complex columns get their own file + tests. Raw
  MUI `Table` only for editable form grids.
- Charts: `@mui/x-charts` in `components/dashboard/charts/`; handle the no-data case explicitly.
- Maps: `useJsApiLoader` with `VITE_GOOGLE_MAP_API_KEY` and a module-scope
  `libraries = ["places"]` (same options everywhere); render only when `isLoaded`.
- Rich text: `react-quill` with `RICH_TEXT_MODULES` / `RICH_TEXT_FORMATS` from
  `utils/quillConfig.js` (module-scope, never rebuilt per render). Render stored HTML with
  `html-react-parser`, not `dangerouslySetInnerHTML`.

## 19. Money, dates and copy

- Money: `formatMoney` (`@/utils/commonUtils`). Format numbers/dates with `Intl`; `dayjs` only when a
  picker or date math needs it.
- Calendar dates are ISO `YYYY-MM-DD` strings, formatted from the string, never via `new Date()`.
  Property "today" comes from the backend. Instants show in viewer local time (`fmtDateTime`).
- No i18n layer: English copy inline. Sentence case; buttons are verbs ("Save", "Add vendor");
  errors say what failed and what to do; no raw codes or stack traces.

## 20. Accessibility and performance

- Every input has a label (shared inputs take `label`/`id`); icon-only buttons get `aria-label`
  (or a `Tooltip` title). Use real `Button`/`IconButton`, not clickable `div`s.
- Stable list keys (ids, never indexes for reorderable lists).
- `useMemo` / `useCallback` for expensive derivations or values passed to memo-sensitive consumers
  (table columns, hook return values); not by default.

## 21. Testing

- Vitest + Testing Library + `user-event` (not `fireEvent`); setup in `test/setup.js`.
- Mock the API module, not the network, with every hook the component uses:
  ```jsx
  const mocks = vi.hoisted(() => ({ options: [] }));
  vi.mock("@/app/api/baseApi", () => ({
    useAdditionalFeeTypeSelectQuery: () => ({ data: mocks.options, isLoading: false }),
  }));
  ```
- Mock `react-redux`'s `useSelector` for permissions; `MemoryRouter` for routing; form fields in a
  small `Harness` (`useForm` + `FormProvider`). Query by role and accessible name.
- Extract pure logic into `.js` helpers and test them without rendering.

## 22. Recipes (golden paths)

**New endpoint + hook**
1. Add it to `app/api/endpoints/<domain>.jsx` (`export default { endpoints: (builder) => ({ ... }) }`).
   New domain file: import it in `baseApi.jsx` and chain `.injectEndpoints(x)` on `extendedApi`.
2. Name it like its neighbours (`inventoryLocationsList` -> `useInventoryLocationsListQuery`).
   Add `providesTags` / `invalidatesTags`; new tag type -> `tagTypes`.
3. Add the generated hook(s) to the `export const { ... } = extendedApi` block.
4. Import the hook from `@/app/api/baseApi` in the page.

**New Add/Edit page with a form** (model: `pages/dashboard/inventory/EditStorageLocation.jsx`)
1. Endpoints: retrieve, create, update (recipe above).
2. Fields: `components/forms/<domain>/<X>Form.jsx`, `useFormContext()` + shared inputs (section 8).
3. Page `pages/dashboard/<domain>/Edit<X>.jsx`: `const { id } = useParams(); const isNew = !id;`,
   retrieve query with `{ skip: isNew }`, create/update mutations, `readOnly` from `useAbility()`,
   `isError` -> Alert with Retry, then `<BaseForm>` wrapping `<XForm>`; `onSubmit` returns the
   mutation result.
4. Route: in `app/router.jsx`, under the domain's `PermissionRoute`, add `route.CREATE` and
   `route.EDIT` children pointing at the same page, each with `handle: { crumb }`.
5. Test the form fields with a `Harness` and the page with mocked `@/app/api/baseApi`.

**New dialog**
1. Confirmation or delete? Use `AlertDialog` / `DeleteDialog`. Stop.
2. Otherwise `components/dialog/<domain>/<X>Dialog.jsx` (model: `dialog/inventory/VendorDialog.jsx`):
   props `open`, `onClose`, plus `onConfirm(payload)` or, if it saves, `onSaved(result)`.
3. Reset local fields when `open` turns true; on error show it inline and keep the dialog open.
4. Parent: `const [editing, setEditing] = useState(null);` and `open={Boolean(editing)}`.

**New table screen / tab** (model: `components/inventory/StorageLocations.jsx`)
1. List endpoint + hook; `const { data = [], isLoading, isError, refetch } = useXListQuery(params)`.
2. `columns` with `accessorKey` or `id`, `header`, `cell: ({ row }) => row.original...`; an
   `actions` column of `CustomIconButton`s gated by `ability.can(...)`.
3. `isError` -> Alert with Retry; otherwise `<DataTable columns data loading emptyMessage />`.
   Filters/page in the URL (`useSearchParams`); server sorting/pagination via Datatable props.
4. Add it to the domain's tabs page: `{ key: "<slug>", label, component: <Xs /> }` in `StyledTabs`.
5. Row actions open dialogs (recipe above) or navigate to the Add/Edit route.

## 23. Review checklist

- [ ] Lint/Prettier clean; tests pass; `@/` imports; files in the right type-first folder.
- [ ] Shared inputs, dialogs, `Datatable`, `useApiHook` used directly; no wrappers, copies, wrapped
      MUI primitives or one-off hooks; shared components hold no domain logic.
- [ ] No prop drilling; route ids via `useParams` / `useSearchParams`.
- [ ] Page forms use `BaseForm` + `<X>Form.jsx`; 409 flows in `onSubmit`.
- [ ] State in its narrowest home; server data only in RTK Query.
- [ ] Hooks from `@/app/api/baseApi`; mutations invalidate every affected screen; live data via tags.
- [ ] Loading, empty and error (with Retry) states handled.
- [ ] Permissions via `useAbility` / `PermissionRoute`; no `canX` drilling.
- [ ] Choices from `app/enum.js`; no secrets in `VITE_*`; no `dangerouslySetInnerHTML`.
- [ ] `formatMoney`; ISO calendar dates; property "today" from backend; time `valueFormat` matches API.
- [ ] Theme tokens; `Grid2`; mobile checked; labels and `aria-label`s present.
- [ ] Dialogs keep input on failed save.
- [ ] Removed fields/features leave no references behind.
- [ ] Tests mock `@/app/api/baseApi` fully and query by role.

## 24. Domain terms (name things with these)

| Term | Meaning |
| --- | --- |
| Company | The tenant account; owns properties, subscription, integrations. |
| User / Profile | User is the login; Profile is that user's membership in one company and carries role, permissions and property access. Permission UI is about profiles. |
| Property / Property group | A rental listing / a named set of properties (`usePropertySelector`). |
| Reservation | A booking on a property; guest name is `guest_first_name` + `guest_last_name`. |
| Platform / OTA | The channel a reservation came from (Airbnb, VRBO, Booking.com); direct bookings show as "SimpliHost". |
| Access code | Smart-lock code: guest code (4 digits, per reservation) or operation code (5-10 digits, per profile). |
| Canned text | Message template with placeholders. |
| Automation | Rule that sends messages or creates tasks on a trigger. |
| Co-hosting | Sharing management of a property between accounts. |
| RU / PriceLabs / Seam | Rentals United (channel manager) / dynamic pricing / smart devices. |
