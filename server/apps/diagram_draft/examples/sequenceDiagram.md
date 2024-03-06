# Sequence Diagram Examples

```mermaid
sequenceDiagram
  Alice->>John: Hello John, how are you?
  John-->>Alice: Great!
  Alice-)John: See you later!
```

```mermaid
sequenceDiagram
  participant Alice
  participant Bob
  Alice->>Bob: Hi Bob
  Bob->>Alice: Hi Alice
```

```mermaid
sequenceDiagram
  actor Alice
  actor Bob
  Alice->>Bob: Hi Bob
  Bob->>Alice: Hi Alice
```

```mermaid
sequenceDiagram
  participant A as Alice
  participant J as John
  A->>J: Hello John, how are you?
  J->>A: Great!
```

```mermaid
sequenceDiagram
  Alice->>Bob: Hello Bob, how are you ?
  Bob->>Alice: Fine, thank you. And you?
  create participant Carl
  Alice->>Carl: Hi Carl!
  create actor D as Donald
  Carl->>D: Hi!
  destroy Carl
  Alice-xCarl: We are too many
  destroy Bob
  Bob->>Alice: I agree
```

```mermaid
  sequenceDiagram
  box Purple Alice & John
  participant A
  participant J
  end
  box Another Group
  participant B
  participant C
  end
  A->>J: Hello John, how are you?
  J->>A: Great!
  A->>B: Hello Bob, how is Charley?
  B->>C: Hello Charley, how are you?
```

```mermaid
sequenceDiagram
  Alice->>John: Hello John, how are you?
  activate John
  John-->>Alice: Great!
  deactivate John
```

```mermaid
sequenceDiagram
  Alice->>+John: Hello John, how are you?
  John-->>-Alice: Great!
```

```mermaid
sequenceDiagram
  Alice->>+John: Hello John, how are you?
  Alice->>+John: John, can you hear me?
  John-->>-Alice: Hi Alice, I can hear you!
  John-->>-Alice: I feel great!
```

```mermaid
sequenceDiagram
  participant John
  Note right of John: Text in note
```

```mermaid
sequenceDiagram
  Alice->John: Hello John, how are you?
  Note over Alice,John: A typical interaction
```

```mermaid
sequenceDiagram
  Alice->John: Hello John, how are you?
  Note over Alice,John: A typical interaction<br/>But now in two lines
```

```mermaid
sequenceDiagram
  Alice->John: Hello John, how are you?
  loop Every minute
    John-->Alice: Great!
  end
```

```mermaid
sequenceDiagram
  Alice->>Bob: Hello Bob, how are you?
  alt is sick
    Bob->>Alice: Not so good :(
  else is well
    Bob->>Alice: Feeling fresh like a daisy
  end
  opt Extra response
    Bob->>Alice: Thanks for asking
  end
```


```mermaid
sequenceDiagram
  par Alice to Bob
    Alice->>Bob: Hello guys!
  and Alice to John
    Alice->>John: Hello guys!
  end
  Bob-->>Alice: Hi Alice!
  John-->>Alice: Hi Alice!
```

```mermaid
sequenceDiagram
  par Alice to Bob
    Alice->>Bob: Go help John
  and Alice to John
    Alice->>John: I want this done today
    par John to Charlie
      John->>Charlie: Can we do this today?
    and John to Diana
      John->>Diana: Can you help us today?
    end
  end
```

```mermaid
sequenceDiagram
  critical Establish a connection to the DB
    Service-->DB: connect
  option Network timeout
    Service-->Service: Log error
  option Credentials rejected
    Service-->Service: Log different error
  end
```

```mermaid
sequenceDiagram
  critical Establish a connection to the DB
    Service-->DB: connect
  end
```

```mermaid
sequenceDiagram
  Consumer-->API: Book something
  API-->BookingService: Start booking process
  break when the booking process fails
    API-->Consumer: show failure
  end
  API-->BillingService: Start billing process
```

```mermaid
sequenceDiagram
  participant Alice
  participant John

  rect rgb(191, 223, 255)
  note right of Alice: Alice calls John.
  Alice->>+John: Hello John, how are you?
  rect rgb(200, 150, 255)
  Alice->>+John: John, can you hear me?
  John-->>-Alice: Hi Alice, I can hear you!
  end
  John-->>-Alice: I feel great!
  end
  Alice ->>+ John: Did you want to go to the game tonight?
  John -->>- Alice: Yeah! See you there.
```

```mermaid
sequenceDiagram
  Alice->>John: Hello John, how are you?
  %% this is a comment
  John-->>Alice: Great!
```

```mermaid
sequenceDiagram
  A->>B: I #9829; you!
  B->>A: I #9829; you #infin; times more!
```

```mermaid
sequenceDiagram
  autonumber
  Alice->>John: Hello John, how are you?
  loop HealthCheck
    John->>John: Fight against hypochondria
  end
  Note right of John: Rational thoughts!
  John-->>Alice: Great!
  John->>Bob: How about you?
  Bob-->>John: Jolly good!
```

```mermaid
sequenceDiagram
  participant Alice
  participant John
  link Alice: Dashboard @ https://dashboard.contoso.com/alice
  link Alice: Wiki @ https://wiki.contoso.com/alice
  link John: Dashboard @ https://dashboard.contoso.com/john
  link John: Wiki @ https://wiki.contoso.com/john
  Alice->>John: Hello John, how are you?
  John-->>Alice: Great!
  Alice-)John: See you later!
```

```mermaid
sequenceDiagram
  participant Alice
  participant John
  links Alice: {"Dashboard": "https://dashboard.contoso.com/alice", "Wiki": "https://wiki.contoso.com/alice"}
  links John: {"Dashboard": "https://dashboard.contoso.com/john", "Wiki": "https://wiki.contoso.com/john"}
  Alice->>John: Hello John, how are you?
  John-->>Alice: Great!
  Alice-)John: See you later!
```

```mermaid
sequenceDiagram
    Alice ->> Bob: Hello Bob, how are you?
    Bob-->>John: How about you John?
    Bob--x Alice: I am good thanks!
    Bob-x John: I am good thanks!
    Note right of John: Bob thinks a long<br/>long time, so long<br/>that the text does<br/>not fit on a row.

    Bob-->Alice: Checking with John...
    Alice->John: Yes... John, how are you?
```

```mermaid
sequenceDiagram
    loop Daily query
        Alice->>Bob: Hello Bob, how are you?
        alt is sick
            Bob->>Alice: Not so good :(
        else is well
            Bob->>Alice: Feeling fresh like a daisy
        end

        opt Extra response
            Bob->>Alice: Thanks for asking
        end
    end
```

```mermaid
sequenceDiagram
    participant Alice
    participant Bob
    Alice->>John: Hello John, how are you?
    loop HealthCheck
        John->>John: Fight against hypochondria
    end
    Note right of John: Rational thoughts<br/>prevail...
    John-->>Alice: Great!
    John->>Bob: How about you?
    Bob-->>John: Jolly good!
```

```mermaid
sequenceDiagram
    participant web as Web Browser
    participant blog as Blog Service
    participant account as Account Service
    participant mail as Mail Service
    participant db as Storage

    Note over web,db: The user must be logged in to submit blog posts
    web->>+account: Logs in using credentials
    account->>db: Query stored accounts
    db->>account: Respond with query result

    alt Credentials not found
        account->>web: Invalid credentials
    else Credentials found
        account->>-web: Successfully logged in

        Note over web,db: When the user is authenticated, they can now submit new posts
        web->>+blog: Submit new post
        blog->>db: Store post data

        par Notifications
            blog--)mail: Send mail to blog subscribers
            blog--)db: Store in-site notifications
        and Response
            blog-->>-web: Successfully posted
        end
    end

```
