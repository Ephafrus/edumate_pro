/// App-wide constants: Firestore collection names, reference data lists, and
/// small configuration values used across the EduMate Pro app.
class Collections {
  static const users = 'users';
  static const staffInvites = 'staffInvites';
  static const classes = 'classes';
  static const learners = 'learners';
  static const applications = 'applications';
  static const payments = 'payments';
  static const chats = 'chats';
  static const mailQueue = 'mailQueue';
  static const activity = 'activity';
}

/// Reference data. In production these could live in Firestore/remote config;
/// they are kept here so forms and filters have a consistent source.
class RefData {
  /// School grades offered, in application-form order.
  static const grades = <String>[
    'Grade R',
    'Grade 1',
    'Grade 2',
    'Grade 3',
    'Grade 4',
    'Grade 5',
    'Grade 6',
    'Grade 7',
    'Grade 8',
    'Grade 9',
    'Grade 10',
    'Grade 11',
    'Grade 12',
  ];

  /// Relationship of the applying guardian to the learner.
  static const guardianRelationships = <String>[
    'Mother',
    'Father',
    'Grandparent',
    'Legal guardian',
    'Foster parent',
    'Other family member',
  ];

  /// Payment purposes offered on the parent payment form.
  static const paymentPurposes = <String>[
    'Registration fee',
    'School fees',
    'Uniform',
    'Stationery',
    'Aftercare',
    'School trip',
    'Other',
  ];

  /// Payment methods a parent can declare on the proof-of-payment form.
  static const paymentMethods = <String>[
    'EFT / bank transfer',
    'Cash deposit',
    'Card payment',
    'Debit order',
  ];

  static const provinces = <String>[
    'Eastern Cape',
    'Free State',
    'Gauteng',
    'KwaZulu-Natal',
    'Limpopo',
    'Mpumalanga',
    'North West',
    'Northern Cape',
    'Western Cape',
  ];

  /// Home languages commonly captured on South African enrolment forms.
  static const languages = <String>[
    'Afrikaans',
    'English',
    'isiNdebele',
    'isiXhosa',
    'isiZulu',
    'Sepedi',
    'Sesotho',
    'Setswana',
    'siSwati',
    'Tshivenda',
    'Xitsonga',
    'Other',
  ];
}

/// EduMate Pro support contact details, shown on the landing page footer.
class Support {
  static const phone = '079 223 0030';
  static const email = 'info@edumatepro.co.za';
}
