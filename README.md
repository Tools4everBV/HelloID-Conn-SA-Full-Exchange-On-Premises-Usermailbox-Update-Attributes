# HelloID-Conn-SA-Full-Exchange-On-Premises-Usermailbox-Update-Attributes

| :information_source: Information                                                                                                                                                                                                                                                                                                                                                          |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description

_HelloID-Conn-SA-Full-Exchange-On-Premises-Usermailbox-Update-Attributes_ is a template designed for use with HelloID Service Automation (SA) Delegated Forms. It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can manage Exchange On-Premises user mailbox attributes directly from HelloID. The following workflow is available:

1.  Search for user mailboxes by name, SamAccountName, alias, or primary SMTP address
2.  Select the target mailbox from the search results
3.  View current attribute values including Display Name and CustomAttributes 1-15
4.  Enter new values for the mailbox attributes
5.  Submit the form to update the mailbox attributes in Exchange On-Premises
6.  Receive confirmation and audit logging of the changes

## Getting started

### Requirements

- **Exchange On-Premises Server**:<br>
  An accessible Exchange On-Premises server with remote PowerShell enabled. The connection URI must be accessible from the HelloID agent or cloud environment.
- **PowerShell Remoting**:<br>
  PowerShell remoting must be enabled on the Exchange server. The connection uses the Microsoft.Exchange configuration endpoint.
- **HelloID Agent** (if not running in cloud):<br>
  A HelloID on-premises agent is required if the Exchange server is not accessible from the cloud. The agent must have network connectivity to the Exchange server.
- **Service Account**:<br>
  A service account with sufficient permissions to connect to Exchange On-Premises and update mailbox attributes. The account must have rights to execute Set-Mailbox and Get-Mailbox cmdlets.

### Connection settings

The following user-defined variables are used by the connector.

| Setting               | Description                                                                  | Mandatory |
| --------------------- | ---------------------------------------------------------------------------- | --------- |
| ExchangeConnectionUri | The URI to the Exchange server (e.g., http://server.domain.local/PowerShell) | Yes       |
| ExchangeAdminUsername | The username of the Exchange administrator account                           | Yes       |
| ExchangeAdminPassword | The password of the Exchange administrator account                           | Yes       |

## Remarks

### Supported Attributes

This connector supports updating the following mailbox attributes:

- Display Name
- CustomAttribute1 through CustomAttribute15

All custom attributes are optional. Only attributes with values will be updated during the Set-Mailbox operation.

### Session Management

The connector uses PowerShell remoting sessions to connect to Exchange On-Premises. Sessions are properly managed with:

- Explicit session creation with authentication and session options
- Limited command import (only Set-Mailbox and Get-Mailbox) for better performance
- Proper session cleanup in finally block to ensure disconnection even on errors

### Search Filter

The datasource supports wildcard searches across multiple mailbox properties:

- Name
- SamAccountName
- Alias
- PrimarySmtpAddress

When searching with "\*" (asterisk), all user mailboxes matching the RecipientTypeDetails filter are returned.

### Performance Optimization

The Get-Mailbox datasource only selects required properties to limit memory usage and improve performance. The selected properties include identity fields, display information, and all 15 custom attributes.

### Error Handling

All scripts implement comprehensive error handling with:

- Detailed error messages including line numbers and context
- Proper audit logging for both success and failure scenarios
- Action message tracking to identify exactly where errors occur
- Graceful session cleanup even when errors are encountered

## Development resources

### Microsoft Documentation

- [Connect to Exchange Servers using Remote PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell)
- [Get-Mailbox cmdlet](https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox)
- [Set-Mailbox cmdlet](https://learn.microsoft.com/en-us/powershell/module/exchange/set-mailbox)
- [Remove-PSSession cmdlet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession)

## Getting help

> :bulb: **Tip:**  
> _For more information on Delegated Forms, please refer to our [documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
