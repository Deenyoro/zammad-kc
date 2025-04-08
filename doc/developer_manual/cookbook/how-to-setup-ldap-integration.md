# How to Setup LDAP Integration

For development purposes, it's possible to set up LDAP integration for a local Zammad instance. However, since the
approach uses an example LDAP service, this is considered unsafe for production. You've been warned!

## Start LDAP Service

You can leverage our LDAP CI Docker container for a quick-n-dirty local service. It comes prefilled with some sample
users and groups.

### With Registry Image

#### CLI

```sh
docker run --name zammad-ldap --detach -p 389:389 -p 636:636 registry.zammad.com/docker/zammad-ldap:stable
```

#### Docker Compose

```yaml
ldap:
  container_name: zammad-ldap
  image: registry.zammad.com/docker/zammad-ldap:stable
  ports:
  - 389:389
  - 636:636
  restart: unless-stopped
```

### With Locally Built Image

#### CLI

```sh
git clone git@git.zammad.com:docker/zammad-ldap.git
cd zammad-ldap
docker build -t zammad-ldap .
docker run --name zammad-ldap --detach -p 389:389 -p 636:636 zammad-ldap
```

#### Docker Compose

```sh
cd /path/to/docker/checkouts
git clone git@git.zammad.com:docker/zammad-ldap.git
```

```yaml
ldap:
  container_name: zammad-ldap
  image: zammad-ldap
  build:
    context: /path/to/docker/checkouts/zammad-ldap
    dockerfile: /path/to/docker/checkouts/zammad-ldap/Dockerfile
  ports:
  - 389:389
  - 636:636
  restart: unless-stopped
```

Where `/path/to/docker/checkouts` points to the the parent folder of your Git checkout.

## Import Certificate

```sh
cd /path/to/docker/checkouts
git clone git@git.zammad.com:docker/zammad-ldap.git
cd /opt/zammad
rails r "SSLCertificate.create!(certificate: Rails.root.join('/path/to/docker/checkouts/zammad-ldap/certs/ca.crt').read)"
```

## Configure LDAP Integration

1. Navigate to the **System > Integrations > LDAP** section in GUI, and click on the **New Source** button.
2. Enter `zammad-ldap` under **Name**.
3. Enter `localhost` under **Host**.
4. Click on **Continue**.
5. Enter `cn=admin,dc=foo,dc=example,dc=com` under **Bind User**.
6. Enter `test` under **Bind Password**.
7. Click on **Continue**.
8. Select _cn (e.g., Nicole)_ LDAP Attribute for _First name_ Zammad Attribute.
9. Select _uid (e.g., nb)_ LDAP Attribute for _Login_ Zammad Attribute.
10. Optionally, add any **Zammad Role** assignments based on **LDAP Group**.
11. Click on **Continue**.
12. Confirm that _14_ users will be created and click on **Save configuration**.

Finally, turn on the toggle switch on top to activate the feature. Wait a bit until the background job does the first
sync. You will then be able to find newly imported users under **Manage > Users** section. All users have `test` set as
their password in the LDAP directory.

## Browse LDAP Directory

You can browse and manage local LDAP directory, if you wish to make any changes.

If you are on macOS, you can use handy **Apache Directory Studio** utility to connect to the local LDAP server.

First, install it via Homebrew:

```sh
arch -x86_64 brew install oracle-jdk
brew install apache-directory-studio
```

Start the newly installed `ApacheDirectoryStudio.app` and add a new connection.

1. Click on **LDAP > New Connection** menu item.
2. Enter `zammad-ldap` under **Connection Name**.
3. Enter `localhost` under **Hostname**.
4. Leave the connection **Encryption method** as _No encryption_ for now.
5. Click on **Next**.
6. Enter `cn=admin,dc=foo,dc=example,dc=com` under **Bind DN or user**.
7. Enter `test` under **Bind password**.
8. Click on **Finish**.

You should now be connected and able to browse LDAP directory using the **LDAP Browser** panel on the left. Drill down
the **Root DSE** to enter the directory and see objects. First level objects are users/accounts, and groups are listed
under `ou=groups`. Note that some groups have a hierarchy defined via their `member` attributes.
