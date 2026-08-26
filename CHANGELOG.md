# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-08-26

### Changed

- Refactored form structure to use single datasource instead of two separate datasources for mailbox selection
- Removed intermediate selected mailbox grid (gridSelectedMailbox) in favor of direct selection from search results
- Improved task script error handling with structured try-catch-finally blocks and detailed action messages
- Enhanced datasource with explicit property selection list to limit memory usage and improve performance
- Implemented dynamic loop for handling custom attributes (1-15) instead of manual handling of each attribute
- Updated session management with explicit session option parameters using splatting for better clarity
- Improved filter logic in datasource to properly handle wildcard searches
- Standardized audit logging messages throughout all scripts for consistency
- Updated task and datasource naming conventions to follow current HelloID standards

### Added

- Support for all 15 custom attributes (previously only supported 7 custom attributes)
- Added explicit commands array for Import-PSSession to only import required cmdlets (Set-Mailbox, Get-Mailbox)
- Added TLS 1.2 enforcement for secure connections

### Fixed

- Improved session cleanup in finally block to ensure proper disconnection even on errors
- Enhanced error messages to include line numbers and detailed context for easier troubleshooting

## [1.0.2] - 2022-08-24

### Added

- Added version number and updated code for SA-agent and auditlogging

## [1.0.1] - 2021-11-16

### Added

- Added version number and updated all-in-one script

## [1.0.0] - 2021-04-29

Initial release of HelloID-Conn-SA-Full-Exchange-On-Premises-Usermailbox-Update-Attributes.

### Added

- Initial release for updating Exchange On-Premises user mailbox attributes
- Support for updating Display Name and CustomAttribute1-7
- Search functionality for mailboxes by name, display name, UPN, or alias
