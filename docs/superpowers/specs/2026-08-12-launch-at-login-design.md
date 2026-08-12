# Launch at Login Design

## Goal

Add a `Launch at Login` toggle to the tray menu. Default state remains off until user enables it.

## Design

Use macOS 13+ `SMAppService.mainApp` because app already requires macOS 14. A small adapter maps Service Management status and register/unregister calls into a testable core controller. Toggle reads controller state when menu opens and after every mutation.

`enabled` and `requiresApproval` both mean registration exists, so toggle stays on. Approval-required state adds `Launch at login requires approval` below controls. Registration errors leave toggle at service-reported state and show `Launch at login: <error>`.

No config-file field, helper executable, login-item bundle, or new dependency.

## Tests

Core tests cover initial state, register, unregister, approval-required state, and failed mutation resync. Full Swift test suite plus release app build verify integration.
