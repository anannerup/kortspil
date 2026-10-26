module Esmakker
  # At vip, in the bank window after trump is named, a seat banks ("Bank",
  # REGLER §2.0 "Bank i bordet"): the melding's points are doubled. The
  # first bank is a seat's other than the melder's (the esmakker's only
  # when the bord allows it); then only the melder may bank once more.
  class Bank < Data.define
    def to_h = {}
  end
end
