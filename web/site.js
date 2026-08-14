(function () {
  const menus = document.querySelectorAll('.derksen-app-menu');

  if (!menus.length) {
    return;
  }

  document.addEventListener('click', (event) => {
    menus.forEach((menu) => {
      if (!menu.contains(event.target)) {
        menu.removeAttribute('open');
      }
    });
  });

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') {
      return;
    }

    menus.forEach((menu) => {
      menu.removeAttribute('open');
    });
  });
})();
