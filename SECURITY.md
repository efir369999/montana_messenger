# Security

Montana Messenger is beta software. If you find a weakness in the application or in the
nodes it talks to, please write to contact@montana.quest rather than opening a public
issue, and give us a reasonable time to close it before publishing.

What is in scope:

- anything that lets a third party read, alter or forge a message or a call;
- anything that reveals who talks to whom, or when, to someone other than the two parties;
- anything that lets one device impersonate another identity.

What is not a finding on its own:

- a dropped or redirected call or message that a party can detect — the transport pair of
  a call is classical by its standard and is treated as admission, not as protection;
- rate limiting, missing headers or version disclosure on the public web site.
