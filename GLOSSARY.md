# OpenEgiz

An open-source industrial digital twin platform for modeling physical assets, ingesting live telemetry, storing time-series history, and visualizing operational state in 2D and 3D.

## Language

### Core Domain

**Twin**:
The live digital representation of a single physical asset, holding its current attributes, features, and access policy.
_Avoid_: Device, thing (outside wire-protocol payloads), entity, node

**Twin Type**:
A reusable template defining the shared structure, default features, and hierarchy metadata for Twins of the same kind.
_Avoid_: Blueprint, model, class, schema

**Telemetry**:
Time-stamped measurements emitted by a physical asset or simulator to update a Twin's state and populate historical series.
_Avoid_: Sensor data, metrics, payload

**Twin Event**:
A state-change notification emitted by the platform whenever a Twin is modified, consumed by time-series storage and external subscribers.
_Avoid_: Webhook, alert, log

**Policy**:
An access-control document governing which subjects may read or write a Twin's attributes and features.
_Avoid_: ACL, role, permission set

**3D Scene**:
A compiled WebGL visualization bundle linked to one or more Twins and rendered inside a dashboard panel.
_Avoid_: Unity build, 3D model, asset pack

**Reference Example**:
A self-contained, runnable industrial scenario (Twin definitions, simulator, and dashboard) shipped with the platform to demonstrate and verify end-to-end behavior.
_Avoid_: Demo, lab, course scenario, contest scenario

### Platform Operations

**Deployment Profile**:
A named runtime configuration balancing onboarding speed against security hardening—specifically the **Dev Profile** (single-command localhost quickstart) and the **Production Profile** (TLS reverse proxy, authenticated messaging, and internal-only storage and APIs).
_Avoid_: Mode, environment, flavor

**Extended API**:
The platform-owned HTTP service providing aggregated Twin, Twin Type, and Policy operations on top of the core digital twin engine for the Grafana interface.
_Avoid_: Middleware, wrapper, helper API

**Plugin Bundle**:
The versioned, rebranded set of Grafana UI extensions packaged as an immutable container artifact for both Docker Compose and Kubernetes deployments.
_Avoid_: Vendor zips, Grafana plugins folder

**Offline Bundle**:
A self-contained, checksum-verified archive containing the repository mirror, pinned container images, and OCI Helm chart required to deploy and run the platform with no internet or external registry access.
_Avoid_: Air-gap dump, tarball backup, NAS dump
