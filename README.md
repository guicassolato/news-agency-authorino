# Authorino Tutorial: News Agency API

Hopefully you are familiar with [Authorino](https://github.com/kuadrant/authorino), the open source, cloud-native authentication/authorization service.

This is a showcase of features of Authorino in the form of a tutorial.

<details>
  <summary>More about Authorino</summary>

  <br/>

  <p>
    If you are not yet familiar with what Authorino is and what it can be used for, we recommend checking out <a href="https://developers.redhat.com/articles/2021/06/18/authorino-making-open-source-cloud-native-api-security-simple-and-flexible">this article</a> for a short intro. It should be a 5 minutes read tops, and it can be very useful for understanding the fundamentals of API authentication/authorization.
  </p>

  <p>
    The most important bits to have in mind while following this tutorial are the overall workflow and internal functioning of Authorino while protecting access to your service or API, with special highlight to the so-called “Authorization JSON” built by Authorino along the "Auth Pipeline" on each request to the protected API.
  </p>

  <p>
    In a nutshell...
  </p>

  ### How Authorino works
  Authorino is a service that operates behind Envoy and that reads its state from [Kubernetes Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/). So, developers declare the desired auth configuration to be enforced for each protected host. (See [Authorino's `AuthConfig` CR](https://github.com/Kuadrant/authorino/blob/main/docs/architecture.md#the-authorino-authconfig-custom-resource-definition-crd).) This auth configuration includes links to the sources of identity that are trusted to access the service, some authorization policies that can either be an implementation of an RBAC system, an ACL, an ABAC system or whatever access control model that makes sense for that protected service.

  Then, consumers of the protected service, who obtained an access token or any form of authentication token supported, can send requests to the service. In request-time, Envoy intercepts the traffic, passes control to Authorino, Authorino verifies the identity, eventually fetches additional metadata required, evaluates the authorization policies, builds a response and handles control back to Envoy, which will either continue the chain of filters, ultimately redirecting the traffic to the protected upstream service, or return right away.

  ### Authorino's "Auth Pipeline"  and the "Authorization JSON"
  On every request to the protected service, Authorino triggers what it calls the "Auth Pipeline". This is basically the series of authentication/authorization evaluators specified in the `AuthConfig`, dividied in 4 phases: identity verification, external metadata fecthing, authorization policies, and dynamic responses.

  Along the steps of applying the `AuthConfig` on a request (i.e. along the "Auth Pipeline"), Authorino builds (and the `AuthConfig` itself can refer to parts of it as well in its definitions) the so-called "Authorization JSON". This JSON starts with contextual information of the request (as passed by Envoy). Then, when an identity object is resolved from whatever authentication token supplied, this identity object goes into the Authorization JSON, as well as any external metadata fetched in the second phase of the Auth Pipeline.

  The phases of the Auth Pipeline can sometimes refer to paths of the Authorization JSON, such as an authorization policy that decides based on an attribute of the identity object that was added to the JSON, or on an attribute of a metadata object, or maybe a dynamic response configuration that digs some data from within the Authorization JSON while building something to send back to the client.
</details>

## Outline

- An API for a news agency has been developed and deployed on a OpenShift cluster
- The API has no intrinsic concept of authentication/authorization
- To add some protection, the API is put behind the [Envoy proxy](https://www.envoyproxy.io/), for consumption by internal and external users – respectively, North-South (NS) and West-East (WE) traffic
- Then 7 iterations of defining (evolving) the authN/authZ scheme, for supporting 7 use cases of the API, begin
  1. Sharing access to the API with teammates (users of the same Kubernetes server) and applications (e.g. a "reader-bot" app)
  2. Extending access to the API to trusted external news writers
  3. Ensuring applications can only READ and LIST news articles, news writers cannot DELETE, and teammates have full access
  4. Opening up the API to federated users from an enterprise Identity Provider (IdP), who can only READ and LIST news articles, using a readers UI SPA
  5. Normalizing access tokens and simplifying authorization policies using RBAC
  6. Geofencing the API: non-admin users from Spain cannot access “sports” category
  7. Rate-limiting the API based on the user’s ID

## The stack

At some point along the 7 iterations, the following components are part of the setup:

- **News API**
  ```
  POST /{category}          Create a news article
  GET /{category}           List news articles
  GET /{category}/{id}      Read a news article
  DELETE /{category}/{id}   Delete a news article
  ```
- **Envoy proxy**<br/>
  Serving the News API w/ cors, ext_authz and rate_limit filters, deployed as a sidecar of the News API
- **Authorino**<br/>
  The authN/authZ service
- **Limitador**<br/>
  The rate limiting service
- **Keycloak**<br/>
  The authorization server federating users of the News API
- **Reader Bot**<br/>
  Application that keeps polling for the list of news articles on different categories
- **Readers UI**<br/>
  Single Page Application (SPA) to read news articles on different categories, after authenticating on Keycloak

**OpenShift**<br/>
All components above run on a same OpenShift cluster. We have tested using OpenShift v4.8.

<details>
  <summary>Why OpenShift and not plain Kubernetes?</summary>

  We have chosen OpenShift mostly for the simplicity involved in handling ingress traffic. With very minimal adaptation nonetheless, the same tutorial could be running on vanilla Kubernetes. The only relevant differences here are, really, that we are using OpenShift `Route`s to handle NS traffic, and some user access tokens – showed further down in the tutorial – that might not be availablein the exact same way in native Kubernetes, but all the rest should be the same.
</details>

**Namespace**<br/>
The resources are all defined in the same cluster namespace, called “authorino-demo”. This is for simplicity and, with a few tweaks, you should be able to change that and split the resources in more namespaces if you want.

**Cert-manager**<br/>
Only one component required by this tutorial as-is does not have an explicit instruction of deployment. This component is [cert-manager](https://docs.cert-manager.io/). Cert-manager is used to generate Authorino’s TLS certificate, whose endpoints for the external authorization calls via gRPC and for OpenID Connect Discovery are served with TLS enabled by default.

Make sure you have cert-manager running in your server before continuing with the tutorial, or follow the [instructions](https://github.com/Kuadrant/authorino/blob/main/docs/deploy.md#tls) in the Authorino docs for deployment without TLS. Some extra tweaks might be needed in the latter case.

## Authorino features covered

The following features of Authorino are covered in this showcase:
- Kubernetes token validation
- API keys authentication
- OpenID Connect JWT verification
- Authorization based on Open Policy Agent (OPA) policies, written in Rego language
- Authorization based on Authorino’s simple JSON pattern-matching authorization policies
- External metadata integration with HTTP GET/GET-by-POST
- Token normalization with Festival Wristbands
- Envoy Dynamic Metadata (for application rate limiting, using [Limitador](https://github.com/3scale-labs/limitador))

## Setup instructions

Clone this repo:

```sh
git clone git@github.com:guicassolato/news-agency-authorino.git && cd news-agency-authorino
```

Fix the OpenShift domain, e.g.:

```sh
ag -l apps.mycluster.example.local | xargs sed -i 's/apps.mycluster.example.local/<your-actual-openshift-apps-domain>/g'
```

Logged in to the OpenShift cluster in the terminal, using the CLI, create the namespace:

```sh
kubectl create namespace authorino-demo
```

### The News API

The News Agency API ("News API" for short) is minimal. It has no authentication or authorization in its own. Whenever a request hits the API and it is a valid endpoint/operation, it serves the request. If it is a `POST` request to `/{category}`, it creates a news article under that news category. Creating an object here means storing it in memory. There is no persisted database. If it is a GET request to `/{category}`, it  serves the list of news articles in the category, that are stored in memory. If it is a `GET` or `DELETE` to `/{category/(article-id}` it serves or deletes the requested object from memory, respectively.

Deploy the New Agency API:

```sh
kubectl -n authorino-demo apply -f news-api/news-api-deploy.yaml
# deployment.apps/news-api created
# service/news-api-internal created
```

At this point, the News API is running, but it is not protected.

### Protecting the API

Deploy Authorino:

```sh
git clone --depth 1 --branch v0.4.0 git@github.com:kuadrant/authorino.git && cd authorino
make install && make deploy AUTHORINO_NAMESPACE=authorino-demo AUTHORINO_IMAGE=quay.io/3scale/authorino:v0.4.0 AUTHORINO_DEPLOYMENT=cluster-wide
```

Remember to get back to the directory where you have cloned the tutorial, in case you have run the command above in the same shell. All the instructions that follow expect your shell to be in this directory.

Put the API behind Envoy (deployed as a sidecar of the News API):

```sh
./envoy/deploy-sidecar.sh
# configmap/envoy created
# deployment.apps/news-api patched
# service/news-api created
# route.route.openshift.io/news-api created
# service "news-api-internal" deleted
```

Together with Envoy, we will be defining a public Kubernetes service for the News API, though the entry point is actually Envoy. We’ll be using this host directly for West-East (WE) traffic. We will also be defining an OpenShift Route, for North-South (NS) traffic.

With that, we should be able to try sending traffic to the API. However, we haven't told Authorino about the existence of the News API yet. Therefore, if we send a request, Envoy will receive this request, it will activate the external authorization service (Authorino), Authorino will look up for an `AuthConfig` for the requested host; it won’t find one, so it will tell Envoy to respond with a 404.

For example, we can send a request to the API asking for the list of news articles in the “sports” category:

```sh
curl -k https://news-api.apps.mycluster.example.local/sports -i
# HTTP/1.1 404 Not Found
# x-ext-auth-reason: Service not found
```

Let us then tell Authorino about the News API…

## Run the use cases

<details>
  <summary><b>Use-case 1:</b> sharing access to the API with <i>teammates</i> (users of the same Kubernetes server) and <i>applications</i> (e.g. reader-bot)</summary>

  <br/>

  The first iteration – or "use-case", if you will – for adding API security to the News API comes from we wanting to share access to the API with our teammates and with applications of them that run in the same cluster as the News API. This is a good use case for API authentication based on Kubernetes user and service account tokens.

  Apply the `AuthConfig`:

  ```sh
  kubectl -n authorino-demo apply -f api-protection-1.yaml
  # authconfig.authorino.3scale.net/news-api-protection created
  ```

  Try sending another request to the API:

  ```sh
  curl -k https://news-api.apps.mycluster.example.local/sports -i
  # HTTP/1.1 401 Unauthorized
  # www-authenticate: Bearer realm="teammates"
  # www-authenticate: Bearer realm="service-accounts"
  # x-ext-auth-reason: {"service-accounts":"credential not found","teammates":"credential not found"}
  ```

  This time, it is not a 404, but a 401 instead. We need a valid access token...

  Let’s impersonate a user of this OpenShift cluster, by getting us a bearer opaque token associated to a user of the cluster. This can be done from the OpenShift Console, or, let’s say, if you are already logged in to the cluster with the CLI, having used an access token to do so, then the token is stored in your kube/config file:

  ```sh
  AUTHENTICATION="Bearer $(yq r ~/.kube/config "users(name==$(kubectl config current-context | awk -F "/" '{ print $3"/"$2 }')).user.token")"
  ```

  Now, yes, we can send a request to the API again:

  ```sh
  curl -k -H "Authorization: $AUTHENTICATION" https://news-api.apps.mycluster.example.local/sports
  # []
  ```

  The reason why this works is because, when we use OpenShift user access token to authenticate, Authorino issues a request to the Kubernetes API to get this token reviewed. Authorino gets an information similar to the `metadata` of the response you get when run you this:

  ```sh
  curl -k -H "Authorization: $AUTHENTICATION" "https://api.mycluster.example.local:6443/apis/user.openshift.io/v1/users/~"
  ```

  It actually does more than that. It explicitly verifies if the token is for the required “audience”. This audience, by the way, is very permissive. We probably do not want to work with that in production, at least not without combining this authentication mode with a more restrictive authorization policy.

  **Consuming the API from inside the cluster**<br/>
  Now, let’s try consuming the News API from inside the cluster, with a client application that authenticates using a Service Account token.

  We have a reader-bot app that reads the Service Account token mounted by kublet within the container, and uses that to keep polling the News API for any news articles in a set of categories.

  By default, the Service Account token is a long lived token, and the audience is the default audience for Kubernetes Service Account tokens – configurable through initialization parameters of the Kubernetes API, which makes sense since these token are mainly used in the Kubernetes authorization system.

  In the case of the reader-bot app, we are customizing the token to have a limited lifetime and a custom “audience” value that equals the hostname and port of the News API. In Authorino, whenever you don’t specify the audiences that the token must include, it assumes the matching requested hostname to be present among the audiences.

  Deploy the reader-bot app:

  ```sh
  kubectl -n authorino-demo apply -f reader-bot/reader-bot-deploy.yaml
  # deployment.apps/reader-bot created
  # serviceaccount/reader-bot-sa created
  ```

  ...and start following the reader-bot's log trail, to see when anything pops up there:

  ```sh
  kubectl -n authorino-demo logs -f $(kubectl -n authorino-demo get pods -l app=reader-bot -o name)
  ```

  **Create a news article**<br/>
  From outside the cluster we have that OpenShift user access token that allowed us to consume the News API impersonating that user. Let’s use that to create an article:

  ```sh
  curl -k -H "Authorization: $AUTHENTICATION" -X POST -d '{"title":"Facebook shut down political ad research, daring authorities to pursue regulation","body":"On Tuesday, Facebook stopped a team of researchers from New York University from studying political ads and COVID-19 misinformation by blocking their personal accounts, pages, apps, and access to its platform. The move was meant to stop NYU’s Ad Observatory from using a browser add-on it launched in 2020 to collect data about the political ads users see on Facebook. (By Christianna Silva)"}' https://news-api.apps.mycluster.example.local/tech
  ```
</details>

<details>
  <summary><b>Use-case 2:</b> extending access to the API to trusted <i>external news writers</i></summary>

  <br/>

  Apply the `AuthConfig`:

  ```sh
  kubectl -n authorino-demo apply -f api-protection-2.yaml
  # authconfig.authorino.3scale.net/news-api-protection configured
  # secret/external-news-writer-1 created
  ```

  Send a request as the user authenticating with API key:

  ```sh
  AUTHENTICATION="API-KEY $(kubectl -n authorino-demo get secret/external-news-writer-1 -o json | jq -r .data.api_key | base64 -d)"

  curl -k -H "Authorization: $AUTHENTICATION" -X POST -d '{"title":"Murder, abuse charges against California foster parents","body":"RIVERSIDE, Calif. (AP) — A Southern California woman who ran a now-shuttered foster home for severely disabled children has been charged with murder and other felonies while her husband faces charges including lewd conduct and willful harm to a child, prosecutors said. (By Associated Press)"}' https://news-api.apps.mycluster.example.local/society
  ```
</details>

<details>
  <summary><b>Use-case 3:</b> ensuring <i>applications can only READ and LIST</i> news articles, <i>news writers cannot DELETE</i>, and <i>teammates have full access</i></summary>

  <br/>

  After iteration 2 ("use-case 2"), all users and apps that consume the News API can all do the same operations. They can create, read and delete news-articles indiscriminately. Iteration 3 adds our first two authorization policies.

  Apply the `AuthConfig`:

  ```sh
  kubectl -n authorino-demo apply -f api-protection-3.yaml
  # authconfig.authorino.3scale.net/news-api-protection configured
  # secret/external-news-writer-1 configured
  ```

  Unfortunately we don’t have any malicious app running in this cluster that tries to either POST or DELETE news articles, but hopefully you will be convinced that our authorization policies work, by trying to DELETE an article using the API key of a news writer:

  _Tip:_ use the ID of news article returned in the response of the last command of the previous use-case, or send a GET request to `/society` to get one.

  ```sh
  curl -k -H "Authorization: $AUTHENTICATION" -X DELETE https://news-api.apps.mycluster.example.local/society/{id} -i
  # HTTP/1.1 403 Forbidden
  # x-ext-auth-reason: Unauthorized
  ```

  Only when we use the teammate token:

  ```sh
  AUTHENTICATION="Bearer $(yq r ~/.kube/config "users(name==$(kubectl config current-context | awk -F "/" '{ print $3"/"$2 }')).user.token")"
  ```

  ...is that we are authorized to delete the article:

  ```sh
  curl -k -H "Authorization: $AUTHENTICATION" -X DELETE https://news-api.apps.mycluster.example.local/society/{id}
  ```
</details>

<details>
  <summary><b>Use-case 4:</b> opening up the API to <i>federated users</i> from an enterprise Identity Provider (IdP), who <i>can only READ and LIST</i> news articles, using a <i>readers UI</i> SPA</summary>

  <br/>

  Managing users, API keys, and even Kubernetes token audiences is fine up to a limited number of API consumers. When things get real, we might need to integrate a proper Identity Provider (IdP). We will be using Authorino OpenID Connect support for that.

  Deploy Keycloak (this step might take a few minutes until the service is ready):

  ```sh
  ./keycloak/install.sh
  ```

  Because Authorino will send requests to Keycloak, to fetch the OpenID Configuration and the JSON Web Key Set (JWKS) it needs to verify ID tokens issued by Keycloak, and because Keycloak uses a self-signed TLS certificate in our deployment here, we need to patch Authorino service appending Keycloak’s CA certificate to its chain of trusted certificates, thus preventing any TLS-related error:

  ```sh
  ./patch-keycloak-cert.sh
  # configmap/ca-pemstore-dev-eng-ocp4-8 created
  # deployment.apps/authorino-controller-manager patched
  ```

  Users whose authentication is handled in Keycloak must be able to read and list news-articles. In fact, they will be doing that through a **Readers UI**. The UI is a Single Page Application (SPA) that negotiates an access token with Keycloak, and the delegated client, on behalf of the user, sends an Ajax requests to the News API.

  Deploy the Readers UI app:

  ```sh
  kubectl -n authorino-demo apply -f readers-ui/readers-ui-deploy.yaml
  # deployment.apps/readers-ui created
  # service/readers-ui created
  # route.route.openshift.io/readers-ui created
  ```

  Create the Keycloak realm:

  ```sh
  kubectl -n authorino-demo apply -f keycloak-realm.yaml
  # keycloakrealm.keycloak.org/news-agency created
  ```

  ...and a Keycloak OAuth client:

  ```sh
  kubectl -n authorino-demo apply -f keycloak-client.yaml
  # keycloakclient.keycloak.org/readers-ui created
  ```

  Finally, deploy the `AuthConfig` corresponding to how we want to protect the API for use-case 4:

  ```sh
  kubectl -n authorino-demo apply -f api-protection-4.yaml
  # authconfig.authorino.3scale.net/news-api-protection configured
  # secret/external-news-writer-1 configured
  # keycloakuser.keycloak.org/john created
  ```

  The manifests includes a Keycloak user named John, that we can authenticate with (username: 'john', password: 'p'). Let’s do that starting by opening the Readers UI in the browser: https://readers-ui.apps.mycluster.example.local.

  We may want to add an exception in the browser for the OpenShift-issued TLS certificate of the external route for the News API. In our requests using curl, we’ve been bypassing server certificate validation, if you noticed.

  In another browser tab, open https://news-api.apps.mycluster.example.local.

  > Note: In production, you shouldn't expect to have this problem, of course, Instead, we recommend favouring properly issued TLS server certificates, signed by well-known certificate authorities.

  Now, play a little with the Readers UI in the browser.
</details>

<details>
  <summary><b>Use-case 5:</b> <i>normalizing access tokens</i> and simplifying authorization policies using <i>RBAC</i></summary>

  <br/>

  In this step, we ensure all sources of identity, which provide user information in different formats to Authorino, are normalized during phase 1 of the Auth Pipeline, in such a way that, whatever authority/authentication method was used by the API consumer to authenticate, the next phases can always trust information regarding user identification and roles can be fetched within the Authorization JSON in the same paths. This allows to simplify the implementation of authorization policies, as well as the configuration for eventual external metadata fetching and dynamic responses.

  The `AuthConfig` for use-case 5 also defines a Festival Wristband configuration, consolidating the normalized user info into one normalized access token issued at the end of a successful Auth Pipeline. The Festival Wristband tokens can then be used to authenticate in subsequent requests to the News API.

  Issuing and accepting wristbands as a valid authentication method are two separate configurations in an Authorino's  `AuthConfig`. A rather common use-case for wristband tokens is the one for Edge Authentication Architecture (EAA), where one `AuthConfig` is responsible for trusting several sources of identity and issues the wristbands, usually in the edge of the network, while multiple other (simpler, more internal) `AuthConfig`s accept only the wristbands as valid method of authentication, and implement all their domain-specific authorization policies using information normalized beforehand.

  Apply the `AuthConfig`:

  ```sh
  kubectl -n authorino-demo apply -f api-protection-5.yaml
  # authconfig.authorino.3scale.net/news-api-protection configured
  # secret/external-news-writer-1 configured
  # keycloakuser.keycloak.org/john configured
  # keycloakuser.keycloak.org/jane created
  # secret/my-signing-key created
  ```

  Send a request, say, as a news writer that list the current articles in the “tech” category:

  ```sh
  AUTHENTICATION="API-KEY $(kubectl -n authorino-demo get secret/external-news-writer-1 -o json | jq -r .data.api_key | base64 -d)"

  curl -k -H "Authorization: $AUTHENTICATION" https://news-api.apps.mycluster.example.local/tech -i
  # HTTP/1.1 200 OK
  # content-type: application/json
  # x-ext-auth-wristband: "<wristband>"
  ```

  Check out the wristband token provided in the response. Store it in a shell variable for authentication later:

  ```sh
  AUTHENTICATION="Bearer <wristband>"
  ```

  Create an article, now using the wristband to authenticate:

  ```sh
  curl -k -H "Authorization: $AUTHENTICATION" -X POST -d '{"title":"Lionel Messi leaving Barcelona after ‘obstacles’ thwart contract renewal","body":"Barcelona have announced that Lionel Messi is leaving the club after “financial and structural obstacles” made it impossible to renew his contract. The forward, who has spent his whole career there, had been expected to re-sign after his deal expired in June. (By David Hytner)"}' https://news-api.apps.mycluster.example.local/sports
  # HTTP/1.1 200 OK
  # content-type: application/json
  ```
</details>

<details>
  <summary><b>Use-case 6:</b> <i>geofencing</i> the API: non-admin users from Spain cannot access “sports” category</summary>

  <br/>

  Let us pretend users from Spain do not like sports news. So, unless you are an admin user, the entire “sports” category will be forbidden in Spain.

  > **Important:** this use-case works if you are in Spain – i.e., if your remote address resolves in a geolocation inquiry to Spain as the country. If you are in another country, replace "Spain" in `api-protection-6.yaml` with the name of your country beforing continuing. You may want to check the exact spelling of the name of your country as returned by http://ip-api.com/json.

  Apply the `AuthConfig`:

  ```sh
  kubectl -n authorino-demo apply -f api-protection-6.yaml
  # authconfig.authorino.3scale.net/news-api-protection configured
  # secret/external-news-writer-1 configured
  # keycloakuser.keycloak.org/john unchanged
  # keycloakuser.keycloak.org/jane configured
  # secret/my-signing-key configured
  ```

  Try reading the sports news as the user ‘john’ in the Readers UI. You should see "403 Forbidden" in the response box.

  The manifests for this use case include another Keycloak user, named Jane (username: 'jane', password: 'p'). Jane has "admin" role. Try reading the sports news as the user ‘jane’ in the Readers UI.

  Using [Tor Browser](https://www.torproject.org/download/), try to read the sports news as ‘john’ in the Readers UI. Tor usually assigns to you a country other than the one you really are, so that's a handy way to try out our use case and see how it behaves outside the established geofence. Alternatively to Tor, you can use any VPN service that maks the user's remote address, particularly assigning one located in a different country.
</details>

<details>
  <summary><b>Use-case 7:</b> <i>rate-limiting</i> the API based on the user’s ID</summary>

  <br/>

  Our last use-case uses [Limitador](https://github.com/3scale-labs/limitador) to enforce rate-limits for the News API, scoped by each user ID. Authorino passes user information back to Envoy, which injects that into a call to the rate-limit service.

  Calls to the News API in this example are limited to 5 requests per minute for each user.

  Deploy Limitador:

  ```sh
  kubectl -n authorino-demo apply -f limitador/limitador-deploy.yaml
  # configmap/limitador created
  # deployment.apps/limitador created
  # service/limitador created
  ```

  Apply the `AuthConfig`:

  ```sh
  kubectl -n authorino-demo apply -f api-protection-7.yaml
  # authconfig.authorino.3scale.net/news-api-protection configured
  # secret/external-news-writer-1 configured
  # keycloakuser.keycloak.org/john unchanged
  # keycloakuser.keycloak.org/jane unchanged
  # secret/my-signing-key configured
  ```

  Try in the Readers UI or in the terminal sending more than 5 requests to the News API with the same user, within the the 1-minute time span.

  Eventually, you should start getting the response "429 Too Many Requests".

  Getting the user a fresh new access token will not work to avoid the limit. As long as the identity subject ("user id") remains the same, so will the corresponding usage and limits be counting, as recorded in Limitador.
</details>

## What can go wrong?

**Expired tokens**<br/>
Sometimes, when you wait enough time between steps of the tutorial, access tokens can expire. We haven't included and explicit step to refresh an access token. If the readers-bot app starts failing to authenticate, or if a command executed in the terminal fails, make sure to use a valid access token, by re-deploying apps that obtain the token on start-up or by exchanging credentials (logging in) again with the corresponding token issuers, in general.

**Missing/invalid shell variables**<br/>
Specially commands involving issuing a request with `curl` from your terminal may fail due to invalid values stored in the shell variables involved – particularly, the `AUTHENTICATION` variable in our examples. Make sure the values stored in the shell variables are the expected ones, by sometimes "echoing" them in the terminal before the critical command.

**TLS issues**<br/>
If you forget the `-k` option in a `curl` command in the terminal or forgot to add exception for the News API TLS server certificate in you browser, some requests may fail unexpectedly.

**Namespace stuck in the "terminating" state**<br/>
Make sure to follow the instructions to cleanup your environment properly after finishing the tutorial. If you have tried cleaning up your environment by just deleting the Kubernetes namespace, sometimes the namespace gets stuck in the "terminating" state. This is usually due to Keycloak not properly triggering its finalizers. If that is the case, make sure to manually delete the blocking resources and/or edit the Keycloak resources removing the finalizers.

## Cleanup

```sh
kubectl -n authorino-demo delete keycloakusers/john
kubectl -n authorino-demo delete keycloakusers/jane
kubectl -n authorino-demo delete -f keycloak-client.yaml
kubectl -n authorino-demo delete -f keycloak-realm.yaml
kubectl delete namespace authorino-demo
```

The steps above will still leave a few cluster-wide resources behind, such as CRDs and `ClusterRole` definitions. This is usually okay and most people don't mind having those created in their clusters for later usage beyond the scope of this tutorial.

If you want to make sure those cluster-wide defined resources also get cleaned up from your cluster, run:

```sh
kustomize build keycloak/install | kubectl delete -f -
```

...and then from the directory where Authorino repo was cloned:

```sh
kustomize build install | kubectl delete -f -
```
