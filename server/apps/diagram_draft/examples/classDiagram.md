# Class Diagrams Examples

```mermaid
---
title: Animal example
---
classDiagram
  note "From Duck till Zebra"
  Animal <|-- Duck
  note for Duck "can fly\ncan swim\ncan dive\ncan help in debugging"
  Animal <|-- Fish
  Animal <|-- Zebra
  Animal : +int age
  Animal : +String gender
  Animal: +isMammal()
  Animal: +mate()
  class Duck{
    +String beakColor
    +swim()
    +quack()
  }
  class Fish{
    -int sizeInFeet
    -canEat()
  }
  class Zebra{
    +bool is_wild
    +run()
  }
```

```mermaid
---
title: Animal example
---
classDiagram
  note "From Duck till Zebra"
  Animal <|-- Duck
  note for Duck "can fly\ncan swim\ncan dive\ncan help in debugging"
  Animal <|-- Fish
  Animal <|-- Zebra
  Animal : +int age
  Animal : +String gender
  Animal: +isMammal()
  Animal: +mate()
  class Duck{
    +String beakColor
    +swim()
    +quack()
  }
  class Fish{
    -int sizeInFeet
    -canEat()
  }
  class Zebra{
    +bool is_wild
    +run()
  }
```

```mermaid
---
title: Bank example
---
classDiagram
  class BankAccount
  BankAccount : +String owner
  BankAccount : +Bigdecimal balance
  BankAccount : +deposit(amount)
  BankAccount : +withdrawal(amount)
```

```mermaid
---
title: Bank example
---
classDiagram
  class BankAccount
  BankAccount : +String owner
  BankAccount : +Bigdecimal balance
  BankAccount : +deposit(amount)
  BankAccount : +withdrawal(amount)
```

```mermaid
classDiagram
  class Animal
  Vehicle <|-- Car
```

```mermaid
classDiagram
  class Animal
  Vehicle <|-- Car
```

```mermaid
classDiagram
  class Animal["Animal with a label"]
  class Car["Car with *! symbols"]
  Animal --> Car
```

```mermaid
classDiagram
  class Animal["Animal with a label"]
  class Car["Car with *! symbols"]
  Animal --> Car
```

```mermaid
classDiagram
  class `Animal Class!`
  class `Car Class`
  `Animal Class!` --> `Car Class`
```

```mermaid
classDiagram
  class `Animal Class!`
  class `Car Class`
  `Animal Class!` --> `Car Class`
```

```mermaid
classDiagram
  class BankAccount
  BankAccount : +String owner
  BankAccount : +BigDecimal balance
  BankAccount : +deposit(amount)
  BankAccount : +withdrawal(amount)
```

```mermaid
classDiagram
  class BankAccount
  BankAccount : +String owner
  BankAccount : +BigDecimal balance
  BankAccount : +deposit(amount)
  BankAccount : +withdrawal(amount)
```

```mermaid
classDiagram
  class BankAccount{
    +String owner
    +BigDecimal balance
    +deposit(amount)
    +withdrawal(amount)
  }
```

```mermaid
classDiagram
  class BankAccount{
    +String owner
    +BigDecimal balance
    +deposit(amount)
    +withdrawal(amount)
  }
```

```mermaid
classDiagram
  class BankAccount{
    +String owner
    +BigDecimal balance
    +deposit(amount) bool
    +withdrawal(amount) int
  }
```

```mermaid
classDiagram
  class BankAccount{
    +String owner
    +BigDecimal balance
    +deposit(amount) bool
    +withdrawal(amount) int
  }
```

```mermaid
classDiagram
  class Square~Shape~{
    int id
    List~int~ position
    setPoints(List~int~ points)
    getPoints() List~int~
  }

  Square : -List~string~ messages
  Square : +setMessages(List~string~ messages)
  Square : +getMessages() List~string~
  Square : +getDistanceMatrix() List~List~int~~
```

```mermaid
classDiagram
  class Square~Shape~{
    int id
    List~int~ position
    setPoints(List~int~ points)
    getPoints() List~int~
  }

  Square : -List~string~ messages
  Square : +setMessages(List~string~ messages)
  Square : +getMessages() List~string~
  Square : +getDistanceMatrix() List~List~int~~
```

```mermaid
classDiagram
  classA <|-- classB
  classC *-- classD
  classE o-- classF
  classG <-- classH
  classI -- classJ
  classK <.. classL
  classM <|.. classN
  classO .. classP

```

```mermaid
classDiagram
  classA <|-- classB
  classC *-- classD
  classE o-- classF
  classG <-- classH
  classI -- classJ
  classK <.. classL
  classM <|.. classN
  classO .. classP

```

```mermaid
classDiagram
  classA --|> classB : Inheritance
  classC --* classD : Composition
  classE --o classF : Aggregation
  classG --> classH : Association
  classI -- classJ : Link(Solid)
  classK ..> classL : Dependency
  classM ..|> classN : Realization
  classO .. classP : Link(Dashed)

```

```mermaid
classDiagram
  classA --|> classB : Inheritance
  classC --* classD : Composition
  classE --o classF : Aggregation
  classG --> classH : Association
  classI -- classJ : Link(Solid)
  classK ..> classL : Dependency
  classM ..|> classN : Realization
  classO .. classP : Link(Dashed)

```

```mermaid
classDiagram
  classA <|-- classB : implements
  classC *-- classD : composition
  classE o-- classF : aggregation
```

```mermaid
classDiagram
  classA <|-- classB : implements
  classC *-- classD : composition
  classE o-- classF : aggregation
```

```mermaid
classDiagram
  Animal <|--|> Zebra
```

```mermaid
classDiagram
  Animal <|--|> Zebra
```

```mermaid
classDiagram
  namespace BaseShapes {
    class Triangle
    class Rectangle {
      double width
      double height
    }
  }
```

```mermaid
classDiagram
  namespace BaseShapes {
    class Triangle
    class Rectangle {
      double width
      double height
    }
  }
```

```mermaid
classDiagram
  Customer "1" --> "*" Ticket
  Student "1" --> "1..*" Course
  Galaxy --> "many" Star : Contains
```

```mermaid
classDiagram
  Customer "1" --> "*" Ticket
  Student "1" --> "1..*" Course
  Galaxy --> "many" Star : Contains
```

```mermaid
classDiagram
  class Shape
  <<interface>> Shape
  Shape : noOfVertices
  Shape : draw()
```

```mermaid
classDiagram
  class Shape
  <<interface>> Shape
  Shape : noOfVertices
  Shape : draw()
```

```mermaid
classDiagram
  class Shape{
    <<interface>>
    noOfVertices
    draw()
  }
  class Color{
    <<enumeration>>
    RED
    BLUE
    GREEN
    WHITE
    BLACK
  }
```

```mermaid
classDiagram
  class Shape{
    <<interface>>
    noOfVertices
    draw()
  }
  class Color{
    <<enumeration>>
    RED
    BLUE
    GREEN
    WHITE
    BLACK
  }

```

```mermaid
classDiagram
  %% This whole line is a comment classDiagram class Shape <<interface>>
  class Shape{
    <<interface>>
    noOfVertices
    draw()
  }
```

```mermaid
classDiagram
  %% This whole line is a comment classDiagram class Shape <<interface>>
  class Shape{
    <<interface>>
    noOfVertices
    draw()
  }
```

```mermaid
classDiagram
  direction RL
  class Student {
    -idCard : IdCard
  }
  class IdCard{
    -id : int
    -name : string
  }
  class Bike{
    -id : int
    -name : string
  }
  Student "1" --o "1" IdCard : carries
  Student "1" --o "1" Bike : rides
```

```mermaid
classDiagram
  direction RL
  class Student {
    -idCard : IdCard
  }
  class IdCard{
    -id : int
    -name : string
  }
  class Bike{
    -id : int
    -name : string
  }
  Student "1" --o "1" IdCard : carries
  Student "1" --o "1" Bike : rides
```

```mermaid
classDiagram
  note "This is a general note"
  note for MyClass "This is a note for a class"
  class MyClass{
  }
```

```mermaid
classDiagram
  class Shape
  link Shape "https://www.github.com" "This is a tooltip for a link"
  class Shape2
  click Shape2 href "https://www.github.com" "This is a tooltip for a link"
```

```mermaid
classDiagram
  class Shape
  callback Shape "callbackFunction" "This is a tooltip for a callback"
  class Shape2
  click Shape2 call callbackFunction() "This is a tooltip for a callback"
```

```mermaid
classDiagram
  class Class01
  class Class02
  callback Class01 "callbackFunction" "Callback tooltip"
  link Class02 "https://www.github.com" "This is a link"
  class Class03
  class Class04
  click Class03 call callbackFunction() "Callback tooltip"
  click Class04 href "https://www.github.com" "This is a link"
```
