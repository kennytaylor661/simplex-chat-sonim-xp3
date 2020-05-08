module Simplex.Messaging.Protocol

%access public export

data Participant = Recipient | Sender | Broker

data Client : Participant -> Type where
  CRecipient : Client Recipient
  CSender    : Client Sender

Key : Type
Key = String

PrivateKey : Type
PrivateKey = String


-- Data structures for participants to store and pass connection information

data Conn : Type where   -- connection info shared between a client and broker
  MkConn : (id : String) -- connection ID to identify it with the broker
        -> (key : Key)   -- public key for broker to verify commands
        -> Conn

record ClientConn where
  constructor MkClientConn
  conn   : Conn   -- same info that broker has for this client
  label  : String -- label for the client to identify connection
  broker : String -- broker URI
  brokerPrivateKey : PrivateKey -- private key to sign commands to broker

newClientConn : ClientConn
newClientConn = MkClientConn (MkConn "" "") "" "" ""

record RcpConn where -- recipient connection data
  constructor MkRcpConn
  clientConn       : ClientConn
  senderPrivateKey : PrivateKey -- private key to decrypt sender messages

newRcpConn : RcpConn
newRcpConn = MkRcpConn newClientConn ""

record Invitation where -- out of band message to sender inviting to connect
  constructor MkInvitation
  conn   : Conn
  broker : String
  senderKey : Key -- public key for sender to encrypt messages

newInvitation : Invitation
newInvitation = MkInvitation (MkConn "" "") "" ""

record SndConn where -- sender connection data
  constructor MkSndConn
  clientConn : ClientConn
  senderKey  : Key -- public key for sender to encrypt messages

newSndConn : SndConn
newSndConn = MkSndConn newClientConn ""


-- connection states for all participants

data ConnectionState =  -- connection states for all participants
            New         -- (participants: all) connection created (or received from sender)
            | Pending   -- (recipient) sent to sender out-of-band
            | Confirmed -- (recipient) confirmed by sender with the broker
            | Secured   -- (all) secured with the broker
            | Disabled  -- (broker, recipient) disabled with the broker by recipient
            | Drained   -- (broker, recipient) drained (no messages)
            | Null      -- (all) not available or removed from the broker

-- broker connection states
data BrokerCS : ConnectionState -> Type where
  BNew      : BrokerCS New
  BSecured  : BrokerCS Secured
  BDisabled : BrokerCS Disabled
  BDrained  : BrokerCS Drained
  BNull     : BrokerCS Null

-- sender connection states
data SenderCS : ConnectionState -> Type where
  SNew       : SenderCS New
  SConfirmed : SenderCS Confirmed
  SSecured   : SenderCS Secured
  SNull      : SenderCS Null

-- allowed participant connection states
data HasState : (p : Participant) -> (s : ConnectionState) -> Type where
  BHasState : {auto prf : BrokerCS s} -> HasState Broker s
  RHasState : HasState Recipient s
  SHasState : {auto prf : SenderCS s} -> HasState Sender s


-- established connection states (used by broker and recipient)
data EstablishedState : ConnectionState -> Type where
  ESecured  : EstablishedState Secured
  EDisabled : EstablishedState Disabled
  EDrained  : EstablishedState Drained


-- dependent types to represent connections for all participants

data BrokerConn : (state : ConnectionState)
               -> {auto prf : HasState Broker state}
               -> Type where
  BCNew      : (recipient : Conn) -> (senderId : String) -> BrokerConn New
  MkBrkConn  : (state : ConnectionState)
            -> (recipient : Conn)
            -> (sender : Conn)
            -> {auto prf : HasState Broker state}
            -> {auto prf : EstablishedState state}
            -> BrokerConn state
  -- 3 constructors below are equivalent to MkBrkConn with some state
  BCSecured  : (recipient : Conn) -> (sender : Conn) -> BrokerConn Secured
  BCDisabled : (recipient : Conn) -> (sender : Conn) -> BrokerConn Disabled
  BCDrained  : (recipient : Conn) -> (sender : Conn) -> BrokerConn Drained
  --
  BCNull     : (id : String) -> BrokerConn Null


-- good broker connection sample
goodBrkConn : BrokerConn Secured
goodBrkConn = MkBrkConn Secured (MkConn "1" "1") (MkConn "2" "2")

-- bad broker connection sample - does not type check
-- badBrkConn : BrokerConn Null
-- badBrkConn = BCEstablished Null (MkConn "1" "1") (MkConn "2" "2")


data RecipientConn : (state : ConnectionState) -> Type where
  RCNew       : (conn : RcpConn) -> (sender : Invitation) -> RecipientConn New
  RCPending   : (conn : RcpConn) -> (sender : Invitation) -> RecipientConn Pending
  RCConfirmed : (conn : RcpConn) -> (sender : Conn) -> RecipientConn Confirmed
  MkRecipientConn   : (state : ConnectionState)
                   -> (conn : RcpConn)
                   -> {auto prf : EstablishedState state}
                   -> RecipientConn state
  -- 3 constructors below are equivalent to MkRcpConn with some state
  RCSecured   : (conn : RcpConn) -> RecipientConn Secured
  RCDisabled  : (conn : RcpConn) -> RecipientConn Disabled
  RCDrained   : (conn : RcpConn) -> RecipientConn Drained
  --
  RCNull      : (conn : RcpConn) -> RecipientConn Null

-- recipient connection sample
goodRcpConn : RecipientConn Secured
goodRcpConn = MkRecipientConn Secured (record
                                        { clientConn = record
                                                        { conn   = MkConn "1" "1"
                                                        , label  = "label"
                                                        , broker = "broker"
                                                        , brokerPrivateKey = "2" }
                                                       newClientConn
                                        , senderPrivateKey = "3" }
                                       newRcpConn)


data SenderConn : (state : ConnectionState)
               -> {auto prf : HasState Sender state}
               -> Type where
  SCNew       : (conn : Invitation) -> SenderConn New
  SCConfirmed : (conn : SndConn) -> SenderConn Confirmed
  SCSecured   : (conn : SndConn) -> SenderConn Secured
  SCNull      : (conn : SndConn) -> SenderConn Null

-- sender connection sample
goodSndConn : SenderConn Secured
goodSndConn = SCSecured (record
                          { clientConn = record
                                          { conn   = MkConn "1" "1"
                                          , label  = "label"
                                          , broker = "broker"
                                          , brokerPrivateKey = "2" }
                                         newClientConn
                          , senderKey = "3" }
                         newSndConn)


-- protocol commands that participants send in relation to specific connection
data Result : (a : Type) -> Type where
  OK   : a -> Result a
  Deny : Result a -- access restriction, not some arbitrary error
  Err  : String -> Result a -- another error

record BrkCreateConnRes where
  constructor MkBrkCreateConnRes
  connId : String
  senderConnId : String

Message : Type
Message = String

-- operator to define connection state change based on the result
infixl 7 <==>, <==|
prefix 8 @@@
prefix 6 ///, >>>

data RBConnState : Type where
  (<==>) : (recipient : ConnectionState)
        -> (broker    : (Nat, ConnectionState)) -- number of messages in connection
        -> {auto prf  : (\(_, s) => HasState Broker s) broker}
        -> RBConnState

data AllConnState : Type where
  (<==|) : (rcpBrk : RBConnState)
        -> (sender : ConnectionState)
        -> {auto prf : HasState Sender sender}
        -> AllConnState

(///) : AllConnState
     -> (AllConnState -> Result a -> AllConnState)
(///) s' = \s, x => case x of
                      OK _  => s'
                      Deny  => s
                      Err _ => s

(>>>) : AllConnState
     -> (AllConnState -> Result a -> AllConnState)
(>>>) s = \_, _ => s


data Command : (ty : Type)
            -> (from : Participant)
            -> (to : Participant)
            -> (state : AllConnState)
            -> ((state : AllConnState) -> Result ty -> AllConnState)
            -> Type where

  CreateConn  : (recipientBrokerKey : Key)
             -> {auto prf : HasState Sender s}
             -> Command BrkCreateConnRes
                  Recipient Broker
                  (Null <==> (Z, Null) <==| s)
                  (>>> New <==> (Z, New)  <==| s)

  Subscribe   : Command () Recipient Broker state (>>> state) -- to improve

  SendInvite  : Invitation
             -> {auto prf : HasState Broker s}
             -> Command () Recipient Sender
                  (New <==> (n, s) <==| Null)
                  (>>> Pending <==> (n, s) <==| New)

  ConfirmConn : (senderBrokerKey : Key)
             -> Command () Sender Broker
                  (s <==> (n, New) <==| New)
                  (>>> s <==> (S n, New) <==| Confirmed)

  PushConfirm : {auto prf : HasState Sender s}
             -> Command () Broker Recipient
                  (Pending <==> (S n, New) <==| s)
                  (>>> Confirmed <==> (n, New) <==| s)

  SecureConn  : (senderBrokerKey : Key)
             -> {auto prf : HasState Sender s}
             -> Command () Recipient Broker
                  (Confirmed <==> (n, New) <==| s)
                  (>>> Secured <==> (n, Secured) <==| s)

  SendWelcome : {auto prf : HasState Broker bs}
             -> Command () Sender Broker
                  (rs <==> (n, Secured) <==| Confirmed)
                  (>>> rs <==> (S n, Secured) <==| Secured)

  PushWelcome : {auto prf : HasState Sender s}
             -> Command () Broker Recipient
                  (Secured <==> (S n, Secured) <==| s)
                  (>>> Secured <==> (n, Secured) <==| s)

  SendMsg     : Message
             -> Command () Sender Broker
                  (rs <==> (n, Secured) <==| Secured)
                  (>>> rs <==> (S n, Secured) <==| Secured)

  PushMsg     : {auto prf : HasState Sender s}
             -> Command () Broker Recipient
                  (Secured <==> (S n, Secured) <==| s)
                  (>>> Secured <==> (n, Secured) <==| s)

  Pure  : (res : Result a) -> Command a from to state state_fn
  (>>=) : Command a from1 to1 state1 state2_fn
          -> ((res : Result a) -> Command b from2 to2 (state2_fn state1 res) state3_fn)
          -> Command b from1 to2 state1 state3_fn